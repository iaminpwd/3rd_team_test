# =================================================================
# scripts/vpn_bgp_setup.ps1 (엔진 완전 재건축 및 라우팅 우회 최종본)
# =================================================================
$ErrorActionPreference = "Stop"

# 0. 필수 기능 및 방화벽 설정
Write-Host "0. 필수 기능 및 방화벽 설정 중..." -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction SilentlyContinue

$fwRules = @(
    @{ Name="Allow-IPsec-IKE-UDP500"; Port="500"; Protocol="UDP" },
    @{ Name="Allow-IPsec-NATT-UDP4500"; Port="4500"; Protocol="UDP" },
    @{ Name="Allow-BGP-TCP179"; Port="179"; Protocol="TCP" }
)
foreach ($rule in $fwRules) {
    try {
        if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction Stop)) {
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port -ErrorAction Stop
        }
    } catch {}
}

# 1. RRAS 엔진 초기화 및 완벽 재건축 (회원님 원본 방식 복원)
Write-Host "1. RRAS 엔진 무조건 철거 후 재건축 중..." -ForegroundColor Cyan

# 찌꺼기가 남아있을 수 있으므로 무조건 철거합니다. (없으면 에러 무시)
try { Uninstall-RemoteAccess -Force -ErrorAction Stop } catch {}
Start-Sleep -Seconds 5

# 빈 껍데기가 아닌, 실제 VPN S2S 라우팅 엔진을 구성합니다. (핵심)
Install-RemoteAccess -VpnType VpnS2S -ErrorAction Stop

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

Write-Host "라우팅 서비스 안전 재시작 중..." -ForegroundColor Cyan
try { Stop-Service RemoteAccess -Force -ErrorAction Stop } catch {}
Start-Sleep -Seconds 2
try { Start-Service RemoteAccess -ErrorAction Stop } catch {}

Write-Host "라우팅 서비스 엔진이 완전히 켜질 때까지 대기 중..." -ForegroundColor Yellow
$svcRetry = 0
while ((Get-Service RemoteAccess).Status -ne 'Running' -and $svcRetry -lt 30) {
    Start-Sleep -Seconds 1
    $svcRetry++
}
if ((Get-Service RemoteAccess).Status -ne 'Running') {
    throw "라우팅 서비스 시작 시간 초과!"
}
Write-Host "▶ 라우팅 엔진 가동 완료!" -ForegroundColor Green

# 2. VPN 인터페이스 및 라우팅 구성
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    # VPC 대역만 할당하여 정상적으로 인터페이스를 생성합니다.
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2 -ErrorAction Stop
    
    Start-Sleep -Seconds 2

    # BGP용 로컬 IP 바인딩
    try {
        Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
    } catch {}
    
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop
    
    # BGP 목적지(Peer IP)로 향하는 트래픽을 터널로 밀어 넣습니다.
    New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction Stop

    Write-Host "[$($t.Name)] IPsec 터널 연결 트리거 중..." -ForegroundColor Yellow
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1

try {
    Add-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -ErrorAction Stop
    Write-Host "▶ BGP 라우터 생성 완료!" -ForegroundColor Green
} catch {
    Set-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -Force -ErrorAction Stop
}

$peers = @(
    @{ Name="AWS-TGW-Peer1"; Local=$BgpLocal1Ip; Peer=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Peer2"; Local=$BgpLocal2Ip; Peer=$BgpPeer2Ip }
)
foreach ($p in $peers) {
    try { Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512 -ErrorAction Stop } catch {}
    try { Start-BgpPeer -Name $p.Name -ErrorAction Stop } catch {}
}

# 4. BGP 경로 광고
Write-Host "4. BGP 경로 광고 중..." -ForegroundColor Cyan
try { Get-BgpCustomRoute -ErrorAction Stop | Remove-BgpCustomRoute -Force -ErrorAction Stop } catch {}
try { Add-BgpCustomRoute -Network "192.168.0.0/24" -ErrorAction Stop } catch {}

# 5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시
Write-Host "5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시..." -ForegroundColor Cyan
foreach ($p in $peers) {
    try { Stop-BgpPeer -Name $p.Name -Force -ErrorAction Stop } catch {}
    try { Start-BgpPeer -Name $p.Name -ErrorAction Stop } catch {}
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green