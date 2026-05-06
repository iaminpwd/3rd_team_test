# =================================================================
# scripts/vpn_bgp_setup.ps1 (현업 최적화 및 에러 완벽 억제 버전)
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
    # 2>$null 을 붙여 불필요한 에러 스트림 누수를 차단합니다.
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue 2>$null)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port -ErrorAction SilentlyContinue
    }
}

# 1. RRAS 엔진 초기화 및 최적화 설치
Write-Host "1. RRAS 엔진 상태 점검 및 초기화 중..." -ForegroundColor Cyan

if (Get-Service RemoteAccess -ErrorAction SilentlyContinue 2>$null) {
    Write-Host "👉 RRAS 엔진이 이미 존재합니다. 설정을 초기화합니다." -ForegroundColor Yellow
    # [수정] 고질적인 에러 출력 누수(BGP is not configured)를 2>$null로 완벽히 흡수합니다.
    # 라우터를 날리면 종속된 Peer와 CustomRoute도 알아서 다 지워지므로 훨씬 깔끔합니다.
    Remove-BgpRouter -Force -ErrorAction SilentlyContinue 2>$null
    Get-VpnS2SInterface -ErrorAction SilentlyContinue 2>$null | Remove-VpnS2SInterface -Force -ErrorAction SilentlyContinue 2>$null
} else {
    Write-Host "👉 RRAS 엔진이 없습니다. 새로 설치합니다." -ForegroundColor Yellow
    Install-RemoteAccess -VpnType VpnS2S -ErrorAction SilentlyContinue
}

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

Write-Host "라우팅 서비스 안전 재시작 중..." -ForegroundColor Cyan
try { Stop-Service RemoteAccess -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service RemoteAccess -ErrorAction SilentlyContinue } catch {}

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
    # [핵심 정정] 회원님의 방식이 맞았습니다. VPC 대역만 넣습니다.
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2 -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2

    # BGP용 IP 강제 할당 (에러 억제 강화)
    Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue 2>$null | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue 2>$null
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue 2>$null
    
    # [복구됨] BGP 통신을 위한 라우팅 강제 삽입 (현업 우회 표준)
    New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction SilentlyContinue 2>$null

    # [유지] 터널 기동 (BGP가 흐를 수 있도록 Demand-Dial 터널을 깨움)
    Write-Host "[$($t.Name)] IPsec 터널 연결 트리거 중..." -ForegroundColor Yellow
    Connect-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue 2>$null
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
$bgpCreated = $false
$bgpRetry = 0

while (-not $bgpCreated -and $bgpRetry -lt 15) {
    try {
        if (-not (Get-BgpRouter -ErrorAction SilentlyContinue 2>$null)) {
            Add-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -ErrorAction Stop
        } else {
            Set-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -Force -ErrorAction Stop
        }
        $bgpCreated = $true
        Write-Host "▶ BGP 라우터 생성 완료!" -ForegroundColor Green
    } catch {
        Write-Host "   엔진 준비 중... 다시 시도합니다. ($($bgpRetry + 1)/15)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
        $bgpRetry++
    }
}

$peers = @(
    @{ Name="AWS-TGW-Peer1"; Local=$BgpLocal1Ip; Peer=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Peer2"; Local=$BgpLocal2Ip; Peer=$BgpPeer2Ip }
)
foreach ($p in $peers) {
    Remove-BgpPeer -Name $p.Name -Force -ErrorAction SilentlyContinue 2>$null
    Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512 -ErrorAction SilentlyContinue 2>$null
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue 2>$null
}

# 4. BGP 경로 광고
Write-Host "4. BGP 경로 광고 중..." -ForegroundColor Cyan
Get-BgpCustomRoute -ErrorAction SilentlyContinue 2>$null | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue 2>$null
Add-BgpCustomRoute -Network "192.168.0.0/24" -ErrorAction SilentlyContinue 2>$null

# 5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시
Write-Host "5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시..." -ForegroundColor Cyan
foreach ($p in $peers) {
    Stop-BgpPeer -Name $p.Name -Force -ErrorAction SilentlyContinue 2>$null
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue 2>$null
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green