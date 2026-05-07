# ─── VPC ──────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = aws_vpc.main.cidr_block
}

# ─── 서브넷 ───────────────────────────────────────────
output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_eks_subnet_ids" {
  description = "EKS 프라이빗 서브넷 ID 목록"
  value       = aws_subnet.private_eks[*].id
}

output "private_devops_subnet_id" {
  description = "DevOps 프라이빗 서브넷 ID (AZ-A)"
  value       = aws_subnet.private_devops.id
}

output "private_main_subnet_id" {
  description = "메인 서버팜 프라이빗 서브넷 ID (AZ-C)"
  value       = aws_subnet.private_main.id
}

output "private_monitor_subnet_id" {
  description = "관리망 프라이빗 서브넷 ID (AZ-C)"
  value       = aws_subnet.private_monitor.id
}

# ─── NAT Gateway ──────────────────────────────────────
output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_eip" {
  description = "NAT Gateway 퍼블릭 IP"
  value       = aws_eip.nat.public_ip
}

# ─── Bastion ──────────────────────────────────────────
output "bastion_public_ip" {
  description = "Bastion EC2 퍼블릭 IP"
  value       = aws_instance.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 인스턴스 ID"
  value       = aws_instance.bastion.id
}

# ─── VPC2 + WorkSpaces ────────────────────────────────
output "vpc2_id" {
  description = "VPC2 (WorkSpaces) ID"
  value       = aws_vpc.workspaces.id
}

output "workspaces_subnet_id" {
  description = "WorkSpaces 서브넷 ID (AZ-A)"
  value       = aws_subnet.workspaces.id
}

output "workspaces_subnet_c_id" {
  description = "WorkSpaces 서브넷 ID (AZ-C) - AD Connector용"
  value       = aws_subnet.workspaces_c.id
}

output "sg_workspaces_id" {
  description = "WorkSpaces Security Group ID"
  value       = aws_security_group.workspaces.id
}

# ─── Security Groups ──────────────────────────────────
output "sg_bastion_id" {
  description = "Bastion Security Group ID"
  value       = aws_security_group.bastion.id
}

output "sg_alb_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "sg_eks_id" {
  description = "EKS Security Group ID"
  value       = aws_security_group.eks.id
}

output "sg_main_id" {
  description = "메인 서버팜 Security Group ID"
  value       = aws_security_group.main.id
}

output "sg_monitor_id" {
  description = "관리망 Security Group ID"
  value       = aws_security_group.monitor.id
}

output "sg_devops_id" {
  description = "DevOps Security Group ID"
  value       = aws_security_group.devops.id
}


output "tunnel1_ip" { value = aws_vpn_connection.vpn.tunnel1_address }


output "tunnel1_psk" { 
  value     = aws_vpn_connection.vpn.tunnel1_preshared_key
  sensitive = true 
}

output "bgp_peer1_ip" { value = aws_vpn_connection.vpn.tunnel1_vgw_inside_address }
output "bgp_local1_ip" { value = aws_vpn_connection.vpn.tunnel1_cgw_inside_address }

output "tunnel2_ip" { value = aws_vpn_connection.vpn.tunnel2_address }


output "tunnel2_psk" { 
  value     = aws_vpn_connection.vpn.tunnel2_preshared_key
  sensitive = true 
}

output "bgp_peer2_ip" { value = aws_vpn_connection.vpn.tunnel2_vgw_inside_address }
output "bgp_local2_ip" { value = aws_vpn_connection.vpn.tunnel2_cgw_inside_address }