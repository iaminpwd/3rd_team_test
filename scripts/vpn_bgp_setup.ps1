# =================================================================
# scripts/vpn_bgp_setup.ps1 (스마트 대기 로직 및 멱등성 완전체 버전)
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

# 1. RRAS 엔진 초기화 및 재설치
Write-Host "1. RRAS 엔진 재설치 중..." -ForegroundColor Cyan
try { 
    Uninstall-RemoteAccess -Force -ErrorAction Stop 
} catch { 
    Write-Host "👉 지울 이전 VPN 설정이 없어 초기화를 건너뜁니다." -ForegroundColor Yellow 
}
Start-Sleep -Seconds 5

Install-RemoteAccess -VpnType VpnS2S -ErrorAction SilentlyContinue
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

# 2. VPN 인터페이스 및 라우팅 구성
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    # 인터페이스 생성
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2 -ErrorAction SilentlyContinue
    
    # 닭과 달걀 딜레마 해결: 터널 강제 기상
    Connect-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3 
    
    # 윈도우가 멋대로 할당한 쓰레기 IPv4(169.254.0.x 등) 강제 청소
    Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    
    # BGP용 IP 및 경로 강제 할당
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue
    New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction SilentlyContinue
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
Write-Host "발견된 서버 IP(BGP Identifier): $myIp"

# BGP 라우터 스마트 생성 (성공할 때까지 재시도)
Write-Host "BGP 라우터 엔진 초기화 및 생성 시도 중..." -ForegroundColor Yellow
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

if (-not $bgpCreated) {
    throw "BGP 라우터 엔진 초기화 실패 (타임아웃)"
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

Write-Host "✅ 모든 설정 완료! 15초 후 통신이 개시됩니다." -ForegroundColor Green
Start-Sleep -Seconds 15