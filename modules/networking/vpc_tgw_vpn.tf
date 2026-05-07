# ---------------------------------------------------------
# VPC 및 기본 네트워크 구성
# ---------------------------------------------------------
resource "aws_vpc" "aws_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "VPC-A-AWS-Cloud" }
}

resource "aws_subnet" "aws_subnet" {
  vpc_id            = aws_vpc.aws_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = "${var.region}a"
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
# 하이브리드 커넥티비티 (TGW + CGW + VPN)
# ---------------------------------------------------------
resource "aws_ec2_transit_gateway" "tgw" {
  amazon_side_asn                 = var.aws_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable" 
  tags = { Name = "TGW-Main" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attach_vpc_a" {
  subnet_ids         = [aws_subnet.private_devops.id, aws_subnet.aws_subnet.id]
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
  ip_address = var.cgw_public_ip 
  type       = "ipsec.1"
  tags = { Name = "CGW-Home-Windows-Server" }
}

resource "aws_vpn_connection" "vpn" {
  customer_gateway_id = aws_customer_gateway.cgw.id
  transit_gateway_id  = aws_ec2_transit_gateway.tgw.id
  type                = aws_customer_gateway.cgw.type
  
  static_routes_only  = false 

  tunnel1_preshared_key = var.tunnel1_psk
  tunnel1_inside_cidr   = "169.254.254.124/30" 
  
  tunnel2_preshared_key = var.tunnel2_psk
  tunnel2_inside_cidr   = "169.254.254.128/30"
  
  
  depends_on = [
    aws_customer_gateway.cgw,
    aws_ec2_transit_gateway.tgw
  ]

  tags = { Name = "VPN-TGW-to-Home" }
}