# ══════════════════════════════════════════════════════
# networking (항상 활성)
# ══════════════════════════════════════════════════════
output "vpc_id" {
  description = "VPC1 ID"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "VPC1 CIDR"
  value       = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.networking.public_subnet_ids
}

output "private_eks_subnet_ids" {
  description = "EKS 프라이빗 서브넷 ID 목록"
  value       = module.networking.private_eks_subnet_ids
}

output "private_devops_subnet_id" {
  description = "DevOps 프라이빗 서브넷 ID"
  value       = module.networking.private_devops_subnet_id
}

output "private_main_subnet_id" {
  description = "메인 서버팜 프라이빗 서브넷 ID"
  value       = module.networking.private_main_subnet_id
}

output "private_monitor_subnet_id" {
  description = "관리망 프라이빗 서브넷 ID"
  value       = module.networking.private_monitor_subnet_id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = module.networking.nat_gateway_id
}

output "nat_eip" {
  description = "NAT Gateway EIP"
  value       = module.networking.nat_eip
}

output "bastion_public_ip" {
  description = "Bastion EC2 퍼블릭 IP"
  value       = module.networking.bastion_public_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 인스턴스 ID"
  value       = module.networking.bastion_instance_id
}

output "sg_bastion_id" {
  description = "Bastion Security Group ID"
  value       = module.networking.sg_bastion_id
}

output "sg_alb_id" {
  description = "ALB Security Group ID"
  value       = module.networking.sg_alb_id
}

output "sg_eks_id" {
  description = "EKS Security Group ID"
  value       = module.networking.sg_eks_id
}

output "sg_devops_id" {
  description = "DevOps Security Group ID"
  value       = module.networking.sg_devops_id
}

output "sg_main_id" {
  description = "메인 서버팜 Security Group ID"
  value       = module.networking.sg_main_id
}

output "sg_monitor_id" {
  description = "관리망 Security Group ID"
  value       = module.networking.sg_monitor_id
}

output "vpc2_id" {
  description = "VPC2 (WorkSpaces) ID"
  value       = module.networking.vpc2_id
}

output "workspaces_subnet_id" {
  description = "WorkSpaces 서브넷 ID (AZ-A)"
  value       = module.networking.workspaces_subnet_id
}

output "workspaces_subnet_c_id" {
  description = "WorkSpaces 서브넷 ID (AZ-C) - AD Connector용"
  value       = module.networking.workspaces_subnet_c_id
}

output "sg_workspaces_id" {
  description = "WorkSpaces Security Group ID"
  value       = module.networking.sg_workspaces_id
}

# ══════════════════════════════════════════════════════
# eks - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "eks_cluster_name" {
#   description = "EKS 클러스터 이름"
#   value       = module.eks.cluster_name
# }
#
# output "eks_cluster_endpoint" {
#   description = "EKS API 엔드포인트"
#   value       = module.eks.cluster_endpoint
# }
#
# output "eks_oidc_provider_arn" {
#   description = "OIDC Provider ARN"
#   value       = module.eks.oidc_provider_arn
# }

# ══════════════════════════════════════════════════════
# auth - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "api_gateway_url" {
#   description = "API Gateway 엔드포인트 URL"
#   value       = module.auth.api_gateway_url
# }
#
# output "lambda_arn" {
#   description = "Lambda 함수 ARN"
#   value       = module.auth.lambda_arn
# }

# ══════════════════════════════════════════════════════
# rds - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "db_endpoint" {
#   description = "RDS 엔드포인트"
#   value       = module.rds.db_endpoint
# }
#
# output "db_port" {
#   description = "RDS 포트"
#   value       = module.rds.db_port
# }

# ══════════════════════════════════════════════════════
# monitoring - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "prometheus_private_ip" {
#   description = "Prometheus/Grafana EC2 프라이빗 IP"
#   value       = module.monitoring.prometheus_private_ip
# }
#
# output "opensearch_private_ip" {
#   description = "OpenSearch EC2 프라이빗 IP"
#   value       = module.monitoring.opensearch_private_ip
# }

# ══════════════════════════════════════════════════════
# workspaces - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "workspace_id" {
#   description = "WorkSpaces 인스턴스 ID"
#   value       = module.workspaces.workspace_id
# }

# ══════════════════════════════════════════════════════
# azure - 주석 해제 후 활성화
# ══════════════════════════════════════════════════════
# output "aks_cluster_name" {
#   description = "AKS 클러스터 이름"
#   value       = module.azure.aks_cluster_name
# }
#
# output "azure_vpn_gateway_ip" {
#   description = "Azure VPN Gateway 퍼블릭 IP"
#   value       = module.azure.vpn_gateway_ip
# }


output "ssm_activation_id" { value = aws_ssm_activation.windows_onprem.id }

output "ssm_activation_code" { 
  value     = aws_ssm_activation.windows_onprem.activation_code
  sensitive = true 
}

# ---------------------------------------------------------
# TGW
# ---------------------------------------------------------
output "vpn_tunnel1_ip" { value = module.networking.tunnel1_ip }

output "vpn_tunnel1_psk" { 
  value     = module.networking.tunnel1_psk
  sensitive = true 
}

output "vpn_bgp_peer1_ip"  { value = module.networking.bgp_peer1_ip }
output "vpn_bgp_local1_ip" { value = module.networking.bgp_local1_ip }

output "vpn_tunnel2_ip" { value = module.networking.tunnel2_ip }

output "vpn_tunnel2_psk" { 
  value     = module.networking.tunnel2_psk
  sensitive = true 
}

output "vpn_bgp_peer2_ip"  { value = module.networking.bgp_peer2_ip }
output "vpn_bgp_local2_ip" { value = module.networking.bgp_local2_ip }