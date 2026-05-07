# =================================================================
# scripts/vpn_bgp_setup.ps1 (엔진 철거 없는 안전한 수술적 초기화본)
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

# 1. RRAS 라우팅 엔진 안전 기동 및 찌꺼기 청소 (데드락 완벽 방지)
Write-Host "1. RRAS 라우팅 엔진 안전 기동 및 초기화 중..." -ForegroundColor Cyan

# 레지스트리 설정 (LAN 라우팅 활성화)
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
try { Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force } catch {}

# 서비스를 무조건 '자동'으로 풀고 기동 (Uninstall을 안 하므로 데드락 안 걸림)
Set-Service -Name RemoteAccess -StartupType Automatic
try { Start-Service RemoteAccess -ErrorAction SilentlyContinue } catch {}

# 엔진 내부 모듈(WMI)이 명령을 받을 수 있을 때까지 찔러보기
$retryCount = 0
$isReady = $false
while ($retryCount -lt 15) {
    try {
        $null = Get-VpnS2SInterface -ErrorAction Stop
        $isReady = $true
        break
    } catch {
        Write-Host "⏳ 엔진 내부 모듈 로딩 대기 중... ($($retryCount * 5)초)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
        $retryCount++
    }
}

if (-not $isReady) { throw "오류: 라우팅 엔진 모듈이 응답하지 않습니다." }

Write-Host "기존 VPN 및 BGP 찌꺼기 안전하게 수술적 제거 중..." -ForegroundColor Yellow
# 에러 무시하고 부드럽게 지우기 (Uninstall 대신 이 방법을 씁니다)
try { Get-VpnS2SInterface -ErrorAction SilentlyContinue | Remove-VpnS2SInterface -Force -ErrorAction SilentlyContinue } catch {}
try { Get-BgpPeer -ErrorAction SilentlyContinue | Remove-BgpPeer -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-BgpRouter -Force -ErrorAction SilentlyContinue } catch {}

# [핵심] BGP 라우팅(LAN Routing) 명시적 기동
try { Enable-RemoteAccessRoutingDomain -Custom -PassThru -ErrorAction SilentlyContinue } catch {}

Write-Host "▶ 라우팅 엔진 가동 준비 완료!" -ForegroundColor Green

# 2. VPN 인터페이스 및 경로 구성
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 인터페이스 생성 중..."
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "0.0.0.0/0:$($t.Metric)" -Protocol IKEv2 -ErrorAction Stop
    
    Write-Host "[$($t.Name)] 어댑터 활성화를 위한 터널 강제 연결 트리거..." -ForegroundColor Yellow
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    Start-Sleep -Seconds 5

    Write-Host "[$($t.Name)] 활성화된 어댑터에 BGP용 로컬 IP 바인딩 중..."
    try {
        Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
    } catch {}
    try { New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop } catch {}
    try { New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction Stop } catch {}
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
try { Add-BgpCustomRoute -Network $OnpremVpcCidr -ErrorAction Stop } catch {}

# 5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시
Write-Host "5. 최종 BGP 세션 확립을 위한 BGP Peer 리프레시..." -ForegroundColor Cyan
foreach ($p in $peers) {
    try { Stop-BgpPeer -Name $p.Name -Force -ErrorAction Stop } catch {}
    try { Start-BgpPeer -Name $p.Name -ErrorAction Stop } catch {}
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green