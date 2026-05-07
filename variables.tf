variable "project" {
  description = "프로젝트 이름 (리소스 태그 prefix)"
  type        = string
  default     = "his"
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "사용할 가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "profile" {
  description = "AWS CLI 프로파일"
  type        = string
  default     = "his-project"
}

# ─── VPC ──────────────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC1 CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

# ─── 서브넷 ───────────────────────────────────────────
variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록 (AZ-A: 대외 서비스 관문, AZ-C: 내부 관리 관문)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.11.0/24"]
}

variable "private_eks_cidrs" {
  description = "EKS 프라이빗 서브넷 CIDR 목록 (AZ-A만)"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "private_devops_cidr" {
  description = "DevOps 서브넷 CIDR (Jenkins, GitLab, Fargate - AZ-A)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "private_main_cidr" {
  description = "메인 서버팜 서브넷 CIDR (ECR, Kafka, RDS, Lambda, API Gateway - AZ-C)"
  type        = string
  default     = "10.0.5.0/24"
}

variable "private_monitor_cidr" {
  description = "관리망 서브넷 CIDR (Prometheus, Grafana, OpenSearch - AZ-C)"
  type        = string
  default     = "10.0.6.0/24"
}

# ─── Bastion ──────────────────────────────────────────
variable "bastion_instance_type" {
  description = "Bastion EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ami_id" {
  description = "Bastion EC2 AMI ID (Amazon Linux 2023, ap-northeast-2)"
  type        = string
  default     = "ami-05d2438ca66594916"
}

variable "bastion_key_name" {
  description = "Bastion EC2 Key Pair 이름"
  type        = string
  default     = "his-bastion-key"
}

variable "allowed_ssh_cidrs" {
  description = "Bastion SSH 허용 CIDR 목록 (팀원 IP)"
  type        = list(string)
  default     = [
    "116.46.68.76/32",
    "49.1.53.163/32",
    "221.168.178.114/32",
    "211.37.27.58/32",
    "211.243.114.16/32",
    "114.202.227.142/32"
  ]
}

variable "vpn_cidr" {
  description = "온프레미스 VPN CIDR (DevOps SG 인바운드 허용)"
  type        = string
  default     = "192.168.0.0/16"
}

# ─── VPC2 (WorkSpaces VDI) ────────────────────────────
variable "vpc2_cidr" {
  description = "VPC2 CIDR 블록 (WorkSpaces VDI)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "workspaces_subnet_cidr" {
  description = "WorkSpaces 서브넷 CIDR (AZ-A)"
  type        = string
  default     = "10.1.1.0/24"
}

variable "workspaces_subnet_cidr_c" {
  description = "WorkSpaces 서브넷 CIDR (AZ-C) - AD Connector용"
  type        = string
  default     = "10.1.2.0/24"
}

# ─── EKS ──────────────────────────────────────────────
variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "EKS 노드 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_desired_size" {
  description = "EKS 노드 기본 수"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "EKS 노드 최소 수"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "EKS 노드 최대 수"
  type        = number
  default     = 4
}

# ─── RDS ──────────────────────────────────────────────
variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "hisdb"
}

variable "db_username" {
  description = "DB 마스터 사용자 이름"
  type        = string
  sensitive   = true
  default     = "hisadmin"
}

variable "db_password" {
  description = "DB 마스터 패스워드 (terraform.tfvars에 설정)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS 스토리지 (GB)"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL 버전"
  type        = string
  default     = "16.3"
}

variable "db_multi_az" {
  description = "RDS Multi-AZ 활성화"
  type        = bool
  default     = true
}

# ─── WorkSpaces ───────────────────────────────────────
variable "ad_directory_id" {
  description = "AD Connector Directory ID (WorkSpaces 연동)"
  type        = string
  default     = ""
}

variable "workspace_bundle_id" {
  description = "WorkSpaces 번들 ID"
  type        = string
  default     = "wsb-gk1wpk43z"
}

# ─── Monitoring ───────────────────────────────────────
variable "jenkins_instance_type" {
  description = "Jenkins EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "gitlab_instance_type" {
  description = "GitLab EC2 인스턴스 타입"
  type        = string
  default     = "t3.large"
}

variable "prometheus_instance_type" {
  description = "Prometheus + Grafana EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "opensearch_instance_type" {
  description = "Amazon OpenSearch Service 인스턴스 타입"
  type        = string
  default     = "t3.small.search"
}

# ─── Azure DR ─────────────────────────────────────────
variable "azure_subscription_id" {
  description = "Azure 구독 ID (terraform.tfvars에 설정)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_tenant_id" {
  description = "Azure 테넌트 ID (terraform.tfvars에 설정)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_client_id" {
  description = "Azure Service Principal Client ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_location" {
  description = "Azure 리전"
  type        = string
  default     = "koreacentral"
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR"
  type        = string
  default     = "10.2.0.0/16"
}

variable "azure_aks_subnet_cidr" {
  description = "AKS 서브넷 CIDR"
  type        = string
  default     = "10.2.1.0/24"
}

variable "azure_gateway_subnet_cidr" {
  description = "Azure VPN Gateway 서브넷 CIDR"
  type        = string
  default     = "10.2.255.0/27"
}

variable "azure_aks_node_count" {
  description = "AKS 노드 수"
  type        = number
  default     = 2
}

variable "azure_aks_node_vm_size" {
  description = "AKS 노드 VM 크기"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aws_vpn_gateway_ip" {
  description = "AWS Site-to-Site VPN 터널 IP (apply 후 입력)"
  type        = string
  default     = ""
}

variable "vpn_shared_key" {
  description = "AWS ↔ Azure VPN 공유키 (terraform.tfvars에 설정)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain_name" {
  description = "서비스 도메인 (Route 53 Failover)"
  type        = string
  default     = ""
}

variable "aws_alb_dns" {
  description = "AWS ALB DNS 이름 (Route 53 Primary 레코드)"
  type        = string
  default     = ""
}



# TGW
variable "aws_asn" {
  description = "AWS Transit Gateway의 BGP ASN"
  type        = number
  default     = 64512
}

variable "onprem_asn" {
  description = "온프레미스(홈 랩)의 BGP ASN"
  type        = number
  default     = 65000
}
