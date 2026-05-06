# =================================================================
# scripts/vpn_bgp_setup.ps1 (엔진 중복 설치 방어 및 스마트 대기 버전)
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
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port -ErrorAction SilentlyContinue
    }
}

# 1. RRAS 엔진 초기화 및 최적화 설치
Write-Host "1. RRAS 엔진 상태 점검 및 초기화 중..." -ForegroundColor Cyan

# ★ 현업 최적화: 이미 설치되어 있다면 지우고 다시 깔지 않고 서비스만 리셋합니다.
if (Get-Service RemoteAccess -ErrorAction SilentlyContinue) {
    Write-Host "👉 RRAS 엔진이 이미 존재합니다. 설정을 초기화합니다." -ForegroundColor Yellow
    # [수정됨] Get 명령어 자체에서 발생하는 "Not Found" 에러를 try-catch로 완벽하게 흡수합니다.
    try { Get-BgpPeer -ErrorAction Stop | Remove-BgpPeer -Force -ErrorAction Stop } catch {}
    try { Get-BgpRouter -ErrorAction Stop | Remove-BgpRouter -Force -ErrorAction Stop } catch {}
    try { Get-VpnS2SInterface -ErrorAction Stop | Remove-VpnS2SInterface -Force -ErrorAction Stop } catch {}
} else {
    Write-Host "👉 RRAS 엔진이 없습니다. 새로 설치합니다." -ForegroundColor Yellow
    Install-RemoteAccess -VpnType VpnS2S -ErrorAction SilentlyContinue
}

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

# 라우팅 서비스 안전 재시작 및 스마트 대기(Waiter)
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

# 2. VPN 인터페이스 및 라우팅 구성 (수정된 현업 표준 방식)
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    # [핵심] AWS VPC 대역뿐만 아니라 BGP Peer IP(/32)도 Demand-Dial 트리거 목록에 포함시킵니다.
    $vpnSubnets = @(
        "${AwsVpcCidr}:$($t.Metric)",
        "$($t.PeerIP)/32:$($t.Metric)"
    )

    # 인터페이스 생성 (IPv4Subnet 파라미터에 배열 전달)
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet $vpnSubnets -Protocol IKEv2 -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2

    # BGP용 IP 강제 할당 (APIPA 랜덤 할당 방지)
    Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue
    
    # [제거됨] New-NetRoute 명령줄은 삭제합니다. 위 IPv4Subnet으로 인해 자동 생성됩니다.

    # [순서 변경] 터널 연결(Connect)은 IP와 라우팅 세팅이 끝난 가장 마지막에 수행해야 안전하게 연결됩니다.
    Write-Host "[$($t.Name)] IPsec 터널 연결 트리거 중..." -ForegroundColor Yellow
    Connect-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
}

# 3. BGP 라우터 및 Peer 구성 (성공할 때까지 재시도 로직 유지)
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
$bgpCreated = $false
$bgpRetry = 0

while (-not $bgpCreated -and $bgpRetry -lt 15) {
    try {
        if (-not (Get-BgpRouter -ErrorAction SilentlyContinue)) {
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
    try { Remove-BgpPeer -Name $p.Name -Force -ErrorAction Stop } catch {}
    Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512 -ErrorAction SilentlyContinue
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue
}

# 4. BGP 경로 광고
Write-Host "4. BGP 경로 광고 중..." -ForegroundColor Cyan
try { Get-BgpCustomRoute -ErrorAction Stop | Remove-BgpCustomRoute -Force -ErrorAction Stop } catch {}
Add-BgpCustomRoute -Network "192.168.0.0/24" -ErrorAction SilentlyContinue

# 5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시
Write-Host "5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시..." -ForegroundColor Cyan
foreach ($p in $peers) {
    Stop-BgpPeer -Name $p.Name -Force -ErrorAction SilentlyContinue
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green