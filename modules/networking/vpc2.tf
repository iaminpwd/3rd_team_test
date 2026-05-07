# ══════════════════════════════════════════════════════
# VPC2 (WorkSpaces VDI) - 10.1.0.0/16
# ══════════════════════════════════════════════════════
resource "aws_vpc" "workspaces" {
  cidr_block           = var.vpc2_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc2-workspaces"
  }
}

# ══════════════════════════════════════════════════════
# WorkSpaces 서브넷 AZ-A (10.1.1.0/24)
# ══════════════════════════════════════════════════════
resource "aws_subnet" "workspaces" {
  vpc_id            = aws_vpc.workspaces.id
  cidr_block        = var.workspaces_subnet_cidr
  availability_zone = var.azs[0]

  tags = {
    Name = "${local.name}-private-workspaces-a"
    Tier = "private"
  }
}

# ══════════════════════════════════════════════════════
# WorkSpaces 서브넷 AZ-C (10.1.2.0/24) - AD Connector용
# ══════════════════════════════════════════════════════
resource "aws_subnet" "workspaces_c" {
  vpc_id            = aws_vpc.workspaces.id
  cidr_block        = var.workspaces_subnet_cidr_c
  availability_zone = var.azs[1]

  tags = {
    Name = "${local.name}-private-workspaces-c"
    Tier = "private"
  }
}

# ══════════════════════════════════════════════════════
# 라우팅 테이블 - VPC2 (WorkSpaces → VPC1 경유)
# ══════════════════════════════════════════════════════
resource "aws_route_table" "workspaces" {
  vpc_id = aws_vpc.workspaces.id

  tags = {
    Name = "${local.name}-rt-workspaces"
  }
}

resource "aws_route_table_association" "workspaces" {
  subnet_id      = aws_subnet.workspaces.id
  route_table_id = aws_route_table.workspaces.id
}

resource "aws_route_table_association" "workspaces_c" {
  subnet_id      = aws_subnet.workspaces_c.id
  route_table_id = aws_route_table.workspaces.id
}
