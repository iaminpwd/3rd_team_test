# ---------------------------------------------------------
# main.tf
# ---------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------
# 1. 보안 데이터 및 설정 (SSM Parameter Store)
# ---------------------------------------------------------
data "aws_ssm_parameter" "tunnel1_psk" {
  name            = "/vpn/home/tunnel1_psk"
  with_decryption = true
}

data "aws_ssm_parameter" "tunnel2_psk" {
  name            = "/vpn/home/tunnel2_psk"
  with_decryption = true
}

# [추가됨] 집 공유기(또는 대상지)의 공인 IP를 SSM에서 동적으로 가져옵니다.
data "aws_ssm_parameter" "cgw_public_ip" {
  name = "/vpn/home/cgw_public_ip"
}

data "aws_ssm_parameter" "windows_password" {
  name = "/vpn/home/windows_password"
}


# ---------------------------------------------------------
# 2. VPC 및 기본 네트워크 구성
# ---------------------------------------------------------
resource "aws_vpc" "aws_vpc" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "VPC-A-AWS-Cloud" }
}

resource "aws_subnet" "aws_subnet" {
  vpc_id            = aws_vpc.aws_vpc.id
  cidr_block        = cidrsubnet(var.aws_vpc_cidr, 8, 1)
  availability_zone = "${var.aws_region}a"
  tags = { Name = "Subnet-A-AWS" }
}

resource "aws_route_table" "aws_rt" {
  vpc_id = aws_vpc.aws_vpc.id
  tags = { Name = "RT-A-AWS" }
}

resource "aws_route_table_association" "aws_rt_assoc" {
  subnet_id      = aws_subnet.aws_subnet.id
  route_table_id = aws_route_table.aws_rt.id
}

# ---------------------------------------------------------
# 3. 하이브리드 커넥티비티 (TGW + CGW + VPN)
# ---------------------------------------------------------
resource "aws_ec2_transit_gateway" "tgw" {
  amazon_side_asn                 = var.aws_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable" 
  tags = { Name = "TGW-Main" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attach_vpc_a" {
  subnet_ids         = [aws_subnet.aws_subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.aws_vpc.id
  tags = { Name = "TGW-Attach-VPC-A" }
}

resource "aws_route" "aws_to_onprem" {
  route_table_id         = aws_route_table.aws_rt.id
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.tgw_attach_vpc_a]
}

resource "aws_customer_gateway" "cgw" {
  bgp_asn    = var.onprem_asn
  # [수정됨] 하드코딩 변수 대신 SSM Parameter Store 값 사용
  ip_address = data.aws_ssm_parameter.cgw_public_ip.value 
  type       = "ipsec.1"
  tags = { Name = "CGW-Home-Windows-Server" }
}

resource "aws_vpn_connection" "vpn" {
  customer_gateway_id = aws_customer_gateway.cgw.id
  transit_gateway_id  = aws_ec2_transit_gateway.tgw.id
  type                = aws_customer_gateway.cgw.type
  
  static_routes_only  = false 

  tunnel1_preshared_key = data.aws_ssm_parameter.tunnel1_psk.value
  tunnel1_inside_cidr   = "169.254.127.124/30"
  
  tunnel2_preshared_key = data.aws_ssm_parameter.tunnel2_psk.value
  tunnel2_inside_cidr   = "169.254.177.40/30"

  tags = { Name = "VPN-TGW-to-Home" }
}

# ---------------------------------------------------------
# 4. 테스트 자원 (Security Group + EC2)
# ---------------------------------------------------------
resource "aws_security_group" "ping_sg" {
  name        = "allow_icmp_from_home"
  description = "Allow ICMP Ping from On-Premise"
  vpc_id      = aws_vpc.aws_vpc.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "SG-Allow-Home-Ping" }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "test_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.aws_subnet.id
  vpc_security_group_ids = [aws_security_group.ping_sg.id]
  tags = { Name = "Test-EC2-Target" }
}

# ---------------------------------------------------------
# 5. SSM Hybrid Activation
# ---------------------------------------------------------
resource "aws_iam_role" "ssm_hybrid_role" {
  name = "SSM-Hybrid-Windows-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_hybrid_attach" {
  role       = aws_iam_role.ssm_hybrid_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ssm_activation" "windows_onprem" {
  name               = "windows-home-server-activation"
  iam_role           = aws_iam_role.ssm_hybrid_role.name
  registration_limit = 5
  depends_on         = [aws_iam_role_policy_attachment.ssm_hybrid_attach]
}


# ---------------------------------------------------------
# 6. 파이프라인으로 넘겨줄 Outputs
# ---------------------------------------------------------
output "ssm_activation_id" {
  value = aws_ssm_activation.windows_onprem.id
}

output "ssm_activation_code" {
  value     = aws_ssm_activation.windows_onprem.activation_code
  sensitive = true
}

output "vpn_tunnel1_ip" {
  value = aws_vpn_connection.vpn.tunnel1_address
}

output "vpn_tunnel1_psk" {
  value     = aws_vpn_connection.vpn.tunnel1_preshared_key
  sensitive = true
}

output "vpn_bgp_peer1_ip" {
  value = aws_vpn_connection.vpn.tunnel1_vgw_inside_address
}

output "vpn_bgp_local1_ip" {
  value = aws_vpn_connection.vpn.tunnel1_cgw_inside_address
}

output "vpn_tunnel2_ip" {
  value = aws_vpn_connection.vpn.tunnel2_address
}

output "vpn_tunnel2_psk" {
  value     = aws_vpn_connection.vpn.tunnel2_preshared_key
  sensitive = true
}

output "vpn_bgp_peer2_ip" {
  value = aws_vpn_connection.vpn.tunnel2_vgw_inside_address
}

output "vpn_bgp_local2_ip" {
  value = aws_vpn_connection.vpn.tunnel2_cgw_inside_address
}