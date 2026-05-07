variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
}

variable "azs" {
  description = "사용할 가용영역 목록"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

# ─── 서브넷 CIDR ───────────────────────────────────────
variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록 (AZ-A: 대외 서비스 관문, AZ-C: 내부 관리 관문)"
  type        = list(string)
}

variable "private_eks_cidrs" {
  description = "EKS 프라이빗 서브넷 CIDR 목록 (AZ-A만)"
  type        = list(string)
}

variable "private_devops_cidr" {
  description = "DevOps 서브넷 CIDR (Jenkins, GitLab, Fargate - AZ-A)"
  type        = string
}

variable "private_main_cidr" {
  description = "메인 서버팜 서브넷 CIDR (ECR, Kafka, RDS, Lambda, API Gateway - AZ-C)"
  type        = string
}

variable "private_monitor_cidr" {
  description = "관리망 서브넷 CIDR (Prometheus, Grafana, OpenSearch - AZ-C)"
  type        = string
}

# ─── Bastion ───────────────────────────────────────────
variable "bastion_instance_type" {
  description = "Bastion EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ami_id" {
  description = "Bastion EC2 AMI ID"
  type        = string
}

variable "bastion_key_name" {
  description = "Bastion EC2 Key Pair 이름"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "SSH 허용 CIDR 목록 (팀원 IP)"
  type        = list(string)
}

variable "vpn_cidr" {
  description = "온프레미스 VPN CIDR"
  type        = string
}

# ─── VPC2 (WorkSpaces VDI) ────────────────────────────
variable "vpc2_cidr" {
  description = "VPC2 CIDR 블록 (WorkSpaces VDI)"
  type        = string
}

variable "workspaces_subnet_cidr" {
  description = "WorkSpaces 서브넷 CIDR (AZ-A)"
  type        = string
}

variable "workspaces_subnet_cidr_c" {
  description = "WorkSpaces 서브넷 CIDR (AZ-C) - AD Connector용"
  type        = string
}


variable "onprem_vpc_cidr" {
  description = "온프레미스(홈 랩)의 CIDR 대역"
  type        = string
}

variable "aws_asn" {
  description = "AWS Transit Gateway의 BGP ASN"
  type        = number
}

variable "onprem_asn" {
  description = "온프레미스(홈 랩)의 BGP ASN"
  type        = number
}

# --- 아래는 SSM에서 읽어와 루트가 넘겨줄 보안 데이터 ---
variable "cgw_public_ip" {
  description = "CGW 퍼블릭 IP"
  type        = string
}

variable "tunnel1_psk" {
  description = "VPN Tunnel 1 PSK"
  type        = string
  sensitive   = true
}

variable "tunnel2_psk" {
  description = "VPN Tunnel 2 PSK"
  type        = string
  sensitive   = true
}