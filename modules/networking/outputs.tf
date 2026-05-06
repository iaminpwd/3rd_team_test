output "vpc_id" { value = aws_vpc.aws_vpc.id }
output "subnet_id" { value = aws_subnet.aws_subnet.id }

output "tunnel1_ip" { value = aws_vpn_connection.vpn.tunnel1_address }

# [수정됨] 쉼표를 제거하고 줄바꿈으로 변경
output "tunnel1_psk" { 
  value     = aws_vpn_connection.vpn.tunnel1_preshared_key
  sensitive = true 
}

output "bgp_peer1_ip" { value = aws_vpn_connection.vpn.tunnel1_vgw_inside_address }
output "bgp_local1_ip" { value = aws_vpn_connection.vpn.tunnel1_cgw_inside_address }

output "tunnel2_ip" { value = aws_vpn_connection.vpn.tunnel2_address }

# [수정됨] 쉼표를 제거하고 줄바꿈으로 변경
output "tunnel2_psk" { 
  value     = aws_vpn_connection.vpn.tunnel2_preshared_key
  sensitive = true 
}

output "bgp_peer2_ip" { value = aws_vpn_connection.vpn.tunnel2_vgw_inside_address }
output "bgp_local2_ip" { value = aws_vpn_connection.vpn.tunnel2_cgw_inside_address }