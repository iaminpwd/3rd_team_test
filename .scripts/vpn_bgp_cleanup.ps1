# FILE: ./scripts/vpn_bgp_cleanup.ps1

Write-Host "1. BGP 정책 및 라우팅 설정 초기화"
# 기존에 쪼개서 만들었던 절대 우선순위 정책과 사용자 지정 라우트를 모두 날립니다.
Get-BgpRoutingPolicy -ErrorAction SilentlyContinue | Remove-BgpRoutingPolicy -Force -ErrorAction SilentlyContinue
Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue

Write-Host "2. BGP 피어(Peer) 및 라우터 제거"
$peers = @("AWS-TGW-Peer1", "AWS-TGW-Peer2")
foreach ($p in $peers) {
    Remove-BgpPeer -Name $p -Force -ErrorAction SilentlyContinue
}
# BGP 라우터 자체를 서버에서 제거합니다.
Remove-BgpRouter -Force -ErrorAction SilentlyContinue

Write-Host "3. VPN Site-to-Site 인터페이스 제거"
$tunnels = @("AWS-TGW-Tunnel1", "AWS-TGW-Tunnel2")
foreach ($t in $tunnels) {
    $iface = Get-VpnS2SInterface -Name $t -ErrorAction SilentlyContinue
    if ($iface) {
        Remove-VpnS2SInterface -Name $t -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "4. 라우팅 서비스 재시작하여 초기화 상태 반영"
# 찌꺼기가 메모리에 남지 않도록 RRAS 서비스를 깔끔하게 재시작합니다.
Restart-Service RemoteAccess -ErrorAction SilentlyContinue

Write-Host "✅ 윈도우 서버 내부의 하이브리드 클라우드(VPN/BGP) 설정이 모두 초기화되었습니다."