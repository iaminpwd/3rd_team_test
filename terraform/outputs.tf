output "ssm_activation_id" { value = aws_ssm_activation.windows_onprem.id }

output "ssm_activation_code" { 
  value     = aws_ssm_activation.windows_onprem.activation_code
  sensitive = true 
}

# ---------------------------------------------------------
# 모듈 아웃풋 릴레이 (쉼표 제거 및 멀티라인 적용)
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