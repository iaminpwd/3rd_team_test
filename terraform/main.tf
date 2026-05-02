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
# 1. 보안 데이터 (SSM Parameter Store)
# ---------------------------------------------------------
data "aws_ssm_parameter" "tunnel1_psk" {
  name            = "/vpn/home/tunnel1_psk"
  with_decryption = true
}

data "aws_ssm_parameter" "tunnel2_psk" {
  name            = "/vpn/home/tunnel2_psk"
  with_decryption = true
}

data "aws_ssm_parameter" "windows_password" {
  name            = "/vpn/home/windows_password"
  with_decryption = true
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
  
  # ★ BGP 핵심: TGW가 VPN으로부터 라우팅 정보를 자동으로 학습하도록 전파 허용
  default_route_table_propagation = "enable" 
  tags = { Name = "TGW-Main" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attach_vpc_a" {
  subnet_ids         = [aws_subnet.aws_subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.aws_vpc.id
  tags = { Name = "TGW-Attach-VPC-A" }
}

# VPC 라우팅: "온프레미스 대역으로 가려면 TGW를 타라" (이건 유지해야 함)
resource "aws_route" "aws_to_onprem" {
  route_table_id         = aws_route_table.aws_rt.id
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.tgw_attach_vpc_a]
}

resource "aws_customer_gateway" "cgw" {
  bgp_asn    = var.onprem_asn
  ip_address = var.cgw_ip_address 
  type       = "ipsec.1"
  tags = { Name = "CGW-Home-Windows-Server" }
}

resource "aws_vpn_connection" "vpn" {
  customer_gateway_id = aws_customer_gateway.cgw.id
  transit_gateway_id  = aws_ec2_transit_gateway.tgw.id
  type                = aws_customer_gateway.cgw.type
  
  # ★ 핵심 반영: BGP 동적 라우팅 사용
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
# 6. Ansible 실행 자동화 (Triggers 반영)
# ---------------------------------------------------------
resource "null_resource" "run_ansible" {
  triggers = {
    playbook_hash = filesha256("../ansible/setup_windows_vpn.yml")
    tunnel1_ip    = aws_vpn_connection.vpn.tunnel1_address
    tunnel2_ip    = aws_vpn_connection.vpn.tunnel2_address
    ssm_id        = aws_ssm_activation.windows_onprem.id
  }

  depends_on = [
    aws_vpn_connection.vpn,
    aws_ssm_activation.windows_onprem
  ]

  provisioner "local-exec" {
    working_dir = "../ansible"
    
    environment = {
      WINRM_PASS    = "windowS!"
      SSM_CODE      = aws_ssm_activation.windows_onprem.activation_code
      SSM_ID        = aws_ssm_activation.windows_onprem.id
      TUNNEL1_IP    = aws_vpn_connection.vpn.tunnel1_address
      TUNNEL1_PSK   = data.aws_ssm_parameter.tunnel1_psk.value
      TUNNEL2_IP    = aws_vpn_connection.vpn.tunnel2_address
      TUNNEL2_PSK   = data.aws_ssm_parameter.tunnel2_psk.value
      
      # ★ 신규 추가: Terraform이 계산한 BGP Inside IP를 동적으로 주입
      # vgw = Virtual Private Gateway (AWS 측 IP)
      # cgw = Customer Gateway (Windows 서버 측 IP)
      BGP_PEER1_IP  = aws_vpn_connection.vpn.tunnel1_vgw_inside_address
      BGP_LOCAL1_IP = aws_vpn_connection.vpn.tunnel1_cgw_inside_address
      BGP_PEER2_IP  = aws_vpn_connection.vpn.tunnel2_vgw_inside_address
      BGP_LOCAL2_IP = aws_vpn_connection.vpn.tunnel2_cgw_inside_address
    }

    command = "ansible-playbook -i inventory.ini setup_windows_vpn.yml"
  }
}

# ---------------------------------------------------------
# 7. Outputs
# ---------------------------------------------------------
output "test_ec2_private_ip" {
  value = aws_instance.test_ec2.private_ip
}

output "ssm_activation_code" {
  value     = aws_ssm_activation.windows_onprem.activation_code
  sensitive = true
}