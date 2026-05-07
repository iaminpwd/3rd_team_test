locals {
  name = var.project
}

# ══════════════════════════════════════════════════════
# VPC1 (메인 서비스) - 10.0.0.0/16
# ══════════════════════════════════════════════════════
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# ══════════════════════════════════════════════════════
# 인터넷 게이트웨이
# ══════════════════════════════════════════════════════
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# ══════════════════════════════════════════════════════
# 퍼블릭 서브넷
# AZ-A (10.0.1.0/24): 대외 서비스 관문 (WAF, ALB, NLB)
# AZ-C (10.0.11.0/24): 내부 관리 관문 (Bastion, NAT)
# ══════════════════════════════════════════════════════
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${count.index == 0 ? "a" : "c"}"
    Tier = "public"
  }
}

# ══════════════════════════════════════════════════════
# EKS 프라이빗 서브넷 (AZ-A: 10.0.2.0/24)
# 대외 서비스 서버팜 (EKS Worker Node, Auto Scaling Group)
# ══════════════════════════════════════════════════════
resource "aws_subnet" "private_eks" {
  count             = length(var.private_eks_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_eks_cidrs[count.index]
  availability_zone = var.azs[0] # AZ-A

  tags = {
    Name                              = "${local.name}-private-eks-a"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ══════════════════════════════════════════════════════
# DevOps 프라이빗 서브넷 (AZ-A: 10.0.4.0/24)
# 개발망 서버팜 (Jenkins, GitLab, Fargate)
# ══════════════════════════════════════════════════════
resource "aws_subnet" "private_devops" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_devops_cidr
  availability_zone = var.azs[0] # AZ-A

  tags = {
    Name = "${local.name}-private-devops"
    Tier = "private"
  }
}

# ══════════════════════════════════════════════════════
# 메인 서버팜 프라이빗 서브넷 (AZ-C: 10.0.5.0/24)
# ECR, Kafka, RDS, Lambda, API Gateway
# ══════════════════════════════════════════════════════
resource "aws_subnet" "private_main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_main_cidr
  availability_zone = var.azs[1] # AZ-C

  tags = {
    Name = "${local.name}-private-main"
    Tier = "private"
  }
}

# ══════════════════════════════════════════════════════
# 관리망 프라이빗 서브넷 (AZ-C: 10.0.6.0/24)
# Prometheus, Grafana, OpenSearch
# ══════════════════════════════════════════════════════
resource "aws_subnet" "private_monitor" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_monitor_cidr
  availability_zone = var.azs[1] # AZ-C

  tags = {
    Name = "${local.name}-private-monitor"
    Tier = "private"
  }
}

# ══════════════════════════════════════════════════════
# NAT Gateway (Public Subnet C, AZ-C: 내부 관리 관문)
# ══════════════════════════════════════════════════════
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[1].id # AZ-C 퍼블릭 서브넷

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ══════════════════════════════════════════════════════
# 라우팅 테이블 구성 (기본 라우팅만 포함)
# ══════════════════════════════════════════════════════
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${local.name}-rt-private" }
}

# ══════════════════════════════════════════════════════
# 온프레미스행 라우팅 (TGW 경유) - 별도 리소스로 분리하여 에러 방지
# ══════════════════════════════════════════════════════
resource "aws_route" "public_to_onprem" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.vpn_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "private_to_onprem" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.vpn_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route_table_association" "private_eks" {
  count          = length(aws_subnet.private_eks)
  subnet_id      = aws_subnet.private_eks[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_devops" {
  subnet_id      = aws_subnet.private_devops.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_main" {
  subnet_id      = aws_subnet.private_main.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_monitor" {
  subnet_id      = aws_subnet.private_monitor.id
  route_table_id = aws_route_table.private.id
}


# ══════════════════════════════════════════════════════
# 퍼블릭 서브넷 라우팅 테이블 연결 (Bastion을 위해 필수!)
# ══════════════════════════════════════════════════════
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}