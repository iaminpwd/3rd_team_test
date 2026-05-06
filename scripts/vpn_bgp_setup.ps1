# =================================================================
# scripts/vpn_bgp_setup.ps1 (최종 수정 버전 - Exact Match 해결)
# =================================================================
$ErrorActionPreference = "Stop"

# 0. 필수 기능 및 방화벽 설정 (기존과 동일)
Write-Host "0. 필수 기능 및 방화벽 설정 중..." -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction SilentlyContinue

$fwRules = @(
    @{ Name="Allow-IPsec-IKE-UDP500"; Port="500"; Protocol="UDP" },
    @{ Name="Allow-IPsec-NATT-UDP4500"; Port="4500"; Protocol="UDP" },
    @{ Name="Allow-BGP-TCP179"; Port="179"; Protocol="TCP" }
)
foreach ($rule in $fwRules) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port
    }
}

# 1. RRAS 엔진 초기화 및 재설치
Write-Host "1. RRAS 엔진 재설치 중..." -ForegroundColor Cyan
Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Install-RemoteAccess -VpnType VpnS2S
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force
Restart-Service RemoteAccess -Force
Start-Sleep -Seconds 5

# 2. VPN 인터페이스 및 라우팅 구성
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    # 인터페이스 생성 (VPC 대역만 지정)
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2 -ErrorAction SilentlyContinue
    
    # BGP용 IP 및 경로 강제 할당 (이게 핵심)
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue
    New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction SilentlyContinue
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan

# [개선] Parameter Store를 뒤질 필요 없이, 현재 서버의 메인 LAN IP를 자동으로 찾아 Identifier로 지정합니다.
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
Write-Host "발견된 서버 IP(BGP Identifier): $myIp"

# 라우터 추가 (Identifier를 동적으로 할당)
Add-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -Force

$peers = @(
    @{ Name="AWS-TGW-Peer1"; Local=$BgpLocal1Ip; Peer=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Peer2"; Local=$BgpLocal2Ip; Peer=$BgpPeer2Ip }
)
foreach ($p in $peers) {
    # 기존 피어 설정을 깔끔하게 밀고 다시 잡습니다.
    Remove-BgpPeer -Name $p.Name -Force -ErrorAction SilentlyContinue
    Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue
}

# 4. BGP 경로 광고 (쪼개지 말고 원본 대역 광고)
Write-Host "4. BGP 경로 광고 중..." -ForegroundColor Cyan
Get-BgpCustomRoute | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue

# 서버가 실제로 가진 192.168.0.0/24 대역을 광고해야 SentCount가 올라갑니다.
Add-BgpCustomRoute -Network "192.168.0.0/24"

Write-Host "✅ 모든 설정 완료! 15초 후 BGP 상태를 확인하세요." -ForegroundColor Green