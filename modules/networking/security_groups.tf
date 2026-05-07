# ══════════════════════════════════════════════════════
# Security Group - Bastion
# 인바운드: SSH(22) → 팀원 IP만
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "bastion" {
  name        = "${local.name}-sg-bastion"
  description = "Bastion host - SSH from team IPs only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-bastion"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

#온프레미스 핑테스트
resource "aws_vpc_security_group_ingress_rule" "bastion_icmp_from_vpn" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow Ping(ICMP) from On-Premises VPN"
  ip_protocol       = "icmp"
  from_port         = -1 # ICMP의 모든 타입 허용
  to_port           = -1
  cidr_ipv4         = var.vpn_cidr
}

# ══════════════════════════════════════════════════════
# Security Group - ALB
# 인바운드: HTTP(80), HTTPS(443) → 0.0.0.0/0
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "ALB - HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ══════════════════════════════════════════════════════
# Security Group - EKS
# 인바운드: ALB SG, Bastion SG, WorkSpaces 서브넷에서만
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "eks" {
  name        = "${local.name}-sg-eks"
  description = "EKS worker nodes - from ALB, Bastion, WorkSpaces only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-eks"
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb" {
  security_group_id            = aws_security_group.eks.id
  description                  = "From ALB HTTPS"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb_http" {
  security_group_id            = aws_security_group.eks.id
  description                  = "From ALB HTTP"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_bastion" {
  security_group_id            = aws_security_group.eks.id
  description                  = "From Bastion (kubectl)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_workspaces" {
  security_group_id = aws_security_group.eks.id
  description       = "From WorkSpaces VDI subnet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.workspaces_subnet_cidr
}

resource "aws_vpc_security_group_ingress_rule" "eks_self" {
  security_group_id            = aws_security_group.eks.id
  description                  = "EKS node-to-node"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks.id
}

resource "aws_vpc_security_group_egress_rule" "eks_all" {
  security_group_id = aws_security_group.eks.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ══════════════════════════════════════════════════════
# Security Group - Main (메인 서버팜: RDS, Kafka, Lambda 등)
# 인바운드: EKS SG에서 PostgreSQL(5432), Devops SG에서 접근
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "main" {
  name        = "${local.name}-sg-main"
  description = "Main server farm - RDS, Kafka, Lambda from EKS and DevOps"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-main"
  }
}

resource "aws_vpc_security_group_ingress_rule" "main_from_eks" {
  security_group_id            = aws_security_group.main.id
  description                  = "PostgreSQL from EKS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.eks.id
}

resource "aws_vpc_security_group_egress_rule" "main_all" {
  security_group_id = aws_security_group.main.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ══════════════════════════════════════════════════════
# Security Group - DevOps (Jenkins, ECR, ELK)
# 인바운드: Bastion SG, VPN CIDR에서만
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "devops" {
  name        = "${local.name}-sg-devops"
  description = "DevOps tools - from Bastion and VPN only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-devops"
  }
}

resource "aws_vpc_security_group_ingress_rule" "devops_from_bastion" {
  security_group_id            = aws_security_group.devops.id
  description                  = "All from Bastion"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "devops_from_vpn" {
  security_group_id = aws_security_group.devops.id
  description       = "All from on-premises VPN"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpn_cidr
}

resource "aws_vpc_security_group_egress_rule" "devops_all" {
  security_group_id = aws_security_group.devops.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ══════════════════════════════════════════════════════
# Security Group - WorkSpaces (VPC2)
# 인바운드: 팀원 IP에서 RDP(3389)
# 아웃바운드: EKS 서브넷 CIDR만 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "workspaces" {
  name        = "${local.name}-sg-workspaces"
  description = "WorkSpaces VDI - RDP inbound, EKS outbound only"
  vpc_id      = aws_vpc.workspaces.id

  tags = {
    Name = "${local.name}-sg-workspaces"
  }
}

resource "aws_vpc_security_group_ingress_rule" "workspaces_rdp" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.workspaces.id
  description       = "RDP from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "workspaces_to_eks_a" {
  security_group_id = aws_security_group.workspaces.id
  description       = "To EKS subnet AZ-A"
  ip_protocol       = "-1"
  cidr_ipv4         = var.private_eks_cidrs[0]
}

# ══════════════════════════════════════════════════════
# Security Group - Monitor (관리망: Prometheus, Grafana, OpenSearch)
# 인바운드: Bastion SG에서만
# 아웃바운드: 전체 허용
# ══════════════════════════════════════════════════════
resource "aws_security_group" "monitor" {
  name        = "${local.name}-sg-monitor"
  description = "Monitor subnet - Grafana, Prometheus, OpenSearch from Bastion only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-sg-monitor"
  }
}

resource "aws_vpc_security_group_ingress_rule" "monitor_grafana" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "Grafana from Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "monitor_prometheus" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "Prometheus from Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 9090
  to_port                      = 9090
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "monitor_opensearch" {
  security_group_id            = aws_security_group.monitor.id
  description                  = "OpenSearch from Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 9200
  to_port                      = 9200
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "monitor_all" {
  security_group_id = aws_security_group.monitor.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
