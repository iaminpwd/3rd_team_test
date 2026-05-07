# TODO: Azure 모듈 구현 완료 후 주석 해제
# provider "azurerm" {
#   features {}
#   subscription_id = var.azure_subscription_id
#   tenant_id       = var.azure_tenant_id
#   client_id       = var.azure_client_id
#   client_secret   = var.azure_client_secret
# }

provider "aws" {
  region  = var.region
  #profile = var.profile

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "Terraform"
    }
  }
}

# ══════════════════════════════════════════════════════
# 1. networking (희석) - 항상 먼저 배포
# ══════════════════════════════════════════════════════
module "networking" {
  source = "./modules/networking"

  project  = var.project
  region   = var.region
  azs      = var.azs
  vpc_cidr = var.vpc_cidr


  public_subnet_cidrs  = var.public_subnet_cidrs
  private_eks_cidrs    = var.private_eks_cidrs
  private_devops_cidr  = var.private_devops_cidr
  private_main_cidr    = var.private_main_cidr
  private_monitor_cidr = var.private_monitor_cidr

  bastion_instance_type = var.bastion_instance_type
  bastion_ami_id        = var.bastion_ami_id
  bastion_key_name      = var.bastion_key_name
  allowed_ssh_cidrs     = var.allowed_ssh_cidrs
  vpn_cidr              = var.vpn_cidr

  vpc2_cidr                = var.vpc2_cidr
  workspaces_subnet_cidr   = var.workspaces_subnet_cidr
  workspaces_subnet_cidr_c = var.workspaces_subnet_cidr_c

  #TGW
  aws_asn         = var.aws_asn
  onprem_asn      = var.onprem_asn
  cgw_public_ip   = data.aws_ssm_parameter.cgw_public_ip.value
  tunnel1_psk     = data.aws_ssm_parameter.tunnel1_psk.value
  tunnel2_psk     = data.aws_ssm_parameter.tunnel2_psk.value
  onprem_vpc_cidr = var.vpn_cidr
}


# ══════════════════════════════════════════════════════
# 2. eks (준수 + 김건) - EKS + Jenkins + GitLab + Fargate
# ══════════════════════════════════════════════════════
# TODO: 구현 완료 후 주석 해제
# module "eks" {
#   source = "./modules/eks"
#
#   project                  = var.project
#   region                   = var.region
#   azs                      = var.azs
#   vpc_id                   = module.networking.vpc_id
#   private_eks_subnet_ids   = module.networking.private_eks_subnet_ids
#   sg_eks_id                = module.networking.sg_eks_id
#   private_devops_subnet_id = module.networking.private_devops_subnet_id
#   sg_devops_id             = module.networking.sg_devops_id
#
#   cluster_version       = var.eks_cluster_version
#   node_instance_type    = var.eks_node_instance_type
#   node_desired_size     = var.eks_node_desired_size
#   node_min_size         = var.eks_node_min_size
#   node_max_size         = var.eks_node_max_size
#   jenkins_instance_type = var.jenkins_instance_type
#   gitlab_instance_type  = var.gitlab_instance_type
#   ami_id                = var.bastion_ami_id
#   bastion_key_name      = var.bastion_key_name
# }

# ══════════════════════════════════════════════════════
# 3. auth (준환) - Lambda + API Gateway + IAM
# ══════════════════════════════════════════════════════
# TODO: 구현 완료 후 주석 해제
# module "auth" {
#   source = "./modules/auth"
#
#   project                = var.project
#   region                 = var.region
#   vpc_id                 = module.networking.vpc_id
#   private_main_subnet_id = module.networking.private_main_subnet_id
#   sg_main_id             = module.networking.sg_main_id
# }

# ══════════════════════════════════════════════════════
# 4. rds (미정) - RDS + Kafka
# ══════════════════════════════════════════════════════
# TODO: 구현 완료 후 주석 해제
# module "rds" {
#   source = "./modules/rds"
#
#   project                = var.project
#   vpc_id                 = module.networking.vpc_id
#   private_main_subnet_id = module.networking.private_main_subnet_id
#   sg_main_id             = module.networking.sg_main_id
#
#   db_name              = var.db_name
#   db_username          = var.db_username
#   db_password          = var.db_password
#   db_instance_class    = var.db_instance_class
#   db_allocated_storage = var.db_allocated_storage
#   db_engine_version    = var.db_engine_version
#   multi_az             = var.db_multi_az
# }

# ══════════════════════════════════════════════════════
# 5. monitoring (미정) - Prometheus + Grafana + OpenSearch
# ══════════════════════════════════════════════════════
# TODO: 구현 완료 후 주석 해제
# module "monitoring" {
#   source = "./modules/monitoring"
#
#   project                   = var.project
#   vpc_id                    = module.networking.vpc_id
#   private_monitor_subnet_id = module.networking.private_monitor_subnet_id
#   sg_monitor_id             = module.networking.sg_monitor_id
#   bastion_key_name          = var.bastion_key_name
#   ami_id                    = var.bastion_ami_id
#   prometheus_instance_type  = var.prometheus_instance_type
#   opensearch_instance_type  = var.opensearch_instance_type
# }

# ══════════════════════════════════════════════════════
# 6. workspaces (우열) - WorkSpaces VDI
# ══════════════════════════════════════════════════════
# TODO: 구현 완료 후 주석 해제
# module "workspaces" {
#   source = "./modules/workspaces"
#
#   project                = var.project
#   vpc2_id                = module.networking.vpc2_id
#   workspaces_subnet_id   = module.networking.workspaces_subnet_id
#   workspaces_subnet_c_id = module.networking.workspaces_subnet_c_id
#   sg_workspaces_id       = module.networking.sg_workspaces_id
#
#   ad_directory_id     = var.ad_directory_id
#   workspace_bundle_id = var.workspace_bundle_id
# }

# ══════════════════════════════════════════════════════
# 7. azure (희석) - AKS + VNet + VPN + Route53 DR
# ══════════════════════════════════════════════════════
# TODO: azurerm provider 주석 해제 후 함께 활성화
# module "azure" {
#   source = "./modules/azure"
#
#   project  = var.project
#   location = var.azure_location
#
#   vnet_cidr           = var.azure_vnet_cidr
#   aks_subnet_cidr     = var.azure_aks_subnet_cidr
#   gateway_subnet_cidr = var.azure_gateway_subnet_cidr
#
#   aks_node_count         = var.azure_aks_node_count
#   aks_node_vm_size       = var.azure_aks_node_vm_size
#   aks_kubernetes_version = var.eks_cluster_version
#
#   aws_vpc_cidr       = var.vpc_cidr
#   aws_vpn_gateway_ip = var.aws_vpn_gateway_ip
#   vpn_shared_key     = var.vpn_shared_key
#
#   domain_name = var.domain_name
#   aws_alb_dns = var.aws_alb_dns
# }

# ---------------------------------------------------------
# 2. Networking 모듈 호출
# ---------------------------------------------------------
