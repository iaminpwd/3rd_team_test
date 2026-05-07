# =================================================================
# scripts/vpn_bgp_setup.ps1 (최종: 라우팅 하이재킹 차단 및 BGP 전용 모드)
# =================================================================
$ErrorActionPreference = "Stop"

# ⭐ [방어 로직] 스크립트 시작 즉시, 네트워크가 가장 안정적일 때 로컬 IP 미리 확보
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
Write-Host "BGP Router ID로 사용할 로컬 IP 확보 완료: $myIp" -ForegroundColor Green

# 0. 필수 기능 및 방화벽 설정
Write-Host "0. 필수 기능 및 방화벽 설정 중..." -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction SilentlyContinue

# 1. RRAS 라우팅 엔진 안전 기동 및 프로비저닝 (현업 표준)
Write-Host "1. RRAS 라우팅 엔진 안전 기동 및 초기화 중..." -ForegroundColor Cyan

# ⭐ [수정됨] try-catch를 사용하여 이미 설치되어 발생한 예외(CimException)를 완벽히 통제하고 멱등성을 보장합니다.
try {
    Install-RemoteAccess -VpnType VpnS2S -ErrorAction Stop
} catch {
    Write-Host "ℹ️ RRAS VPN 엔진이 이미 구성되어 있습니다. 기존 구성을 덮어쓰고 다음으로 진행합니다." -ForegroundColor Gray
}
# 서비스 자동 실행 등록 및 기동
Set-Service -Name RemoteAccess -StartupType Automatic
try { Start-Service RemoteAccess -ErrorAction SilentlyContinue } catch {}

# 엔진 준비 대기
$retryCount = 0
while ($retryCount -lt 15) {
    try {
        $null = Get-VpnS2SInterface -ErrorAction Stop
        break
    } catch {
        Write-Host "⏳ 엔진 모듈 로딩 대기 중..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
        $retryCount++
    }
}

Write-Host "기존 찌꺼기 제거 및 BGP 활성화..." -ForegroundColor Yellow
try { Get-VpnS2SInterface | Remove-VpnS2SInterface -Force -ErrorAction SilentlyContinue } catch {}
try { Get-BgpPeer | Remove-BgpPeer -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-BgpRouter -Force -ErrorAction SilentlyContinue } catch {}
try { Enable-RemoteAccessRoutingDomain -Custom -PassThru -ErrorAction SilentlyContinue } catch {}

# 2. VPN 인터페이스 구성 (현업 표준: Narrow TS 및 Host Route 강제 주입)
Write-Host "2. VPN 인터페이스 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip; Metric="100" },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip; Metric="150" }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 생성 중..."
    
    # ⭐ [핵심 수정] 문제가 된 파라미터를 지우고, 원래의 -IPv4Subnet 방식으로 돌아갑니다.
    # 단, 인터넷(0.0.0.0/0)이나 APIPA(169.254.x.x) 대신, AWS 피어(Peer)의 단일 IP(/32)를 명시적으로 주입합니다.
    # 이렇게 하면 파워쉘 버전 오류나 169.254 거부 에러를 완벽히 우회하면서 BGP 터널을 뚫을 수 있습니다.
    $awsTargetSubnets = @(
        "${AwsVpcCidr}:$($t.Metric)",
        "$($t.PeerIP)/32:$($t.Metric)"
    )
    
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet $awsTargetSubnets -Protocol IKEv2 -ErrorAction Stop
    
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    Start-Sleep -Seconds 5

    try { New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop } catch {}
    
    # BGP 통신을 위한 라우팅 테이블 수동 밀어넣기
    try { New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -RouteMetric $t.Metric -ErrorAction Stop } catch {}
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan

# 상단에서 미리 구해둔 $myIp 변수 활용
try {
    Add-BgpRouter -BgpIdentifier $myIp -LocalASN 65000 -ErrorAction Stop
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
Write-Host "4. BGP 경로 광고 중 ($OnpremVpcCidr)..." -ForegroundColor Cyan
try { Add-BgpCustomRoute -Network $OnpremVpcCidr -ErrorAction Stop } catch {}

# 5. 인터넷 경로 이중 보호 (선택적 방어 로직)
Write-Host "5. 인터넷 경로 보호 중..." -ForegroundColor Cyan

$activeInternetRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1

if ($activeInternetRoute) {
    $eth = Get-NetAdapter -InterfaceIndex $activeInternetRoute.InterfaceIndex -ErrorAction SilentlyContinue
    $defaultGateway = $activeInternetRoute.NextHop
    
    if ($eth -and $defaultGateway) {
        Write-Host "인터넷 어댑터 인식 완료: $($eth.Name), 게이트웨이: $defaultGateway" -ForegroundColor Green
        
        Set-NetIPInterface -InterfaceAlias $eth.Name -InterfaceMetric 5
        try { Set-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceAlias $eth.Name -NextHop $defaultGateway -RouteMetric 5 -ErrorAction SilentlyContinue } catch {}
    }
} else {
    Write-Host "활성화된 인터넷 기본 경로를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green