# scripts/vpn_bgp_cleanup.ps1
Write-Host "1. BGP 정책 및 라우팅 설정 초기화"
Get-BgpRoutingPolicy -ErrorAction SilentlyContinue | Remove-BgpRoutingPolicy -Force -ErrorAction SilentlyContinue
Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue

Write-Host "2. BGP 피어(Peer) 및 라우터 제거"
$peers = @("AWS-TGW-Peer1", "AWS-TGW-Peer2")
foreach ($p in $peers) {
    Remove-BgpPeer -Name $p -Force -ErrorAction SilentlyContinue
}
Remove-BgpRouter -Force -ErrorAction SilentlyContinue

Write-Host "3. VPN Site-to-Site 인터페이스 제거"
$tunnels = @("AWS-TGW-Tunnel1", "AWS-TGW-Tunnel2")
foreach ($t in $tunnels) {
    Remove-VpnS2SInterface -Name $t -Force -ErrorAction SilentlyContinue
}
Write-Host "4. 라우팅 서비스 재시작하여 초기화 상태 반영"
Restart-Service RemoteAccess -ErrorAction SilentlyContinue

# ===== [추가된 핵심 부분] =====
Write-Host "5. RRAS 엔진 구성 완전 초기화 (현업 표준 선언적 초기화)"
Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue
# ==============================

Write-Host "✅ 윈도우 서버 내부의 하이브리드 클라우드(VPN/BGP) 설정이 모두 초기화되었습니다."