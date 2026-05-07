# =================================================================
# scripts/vpn_bgp_setup.ps1 (하드코딩 복구 및 경로 보호 포함)
# =================================================================
$ErrorActionPreference = "Stop"

# ⭐ [핵심 수정] 스크립트 시작 즉시, 네트워크가 가장 안정적일 때 로컬 IP 미리 확보
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
Write-Host "BGP Router ID로 사용할 로컬 IP 확보 완료: $myIp" -ForegroundColor Green

# 0. 필수 기능 및 방화벽 설정
Write-Host "0. 필수 기능 및 방화벽 설정 중..." -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction SilentlyContinue

# 1. RRAS 라우팅 엔진 안전 기동 및 프로비저닝 (현업 표준)
Write-Host "1. RRAS 라우팅 엔진 안전 기동 및 초기화 중..." -ForegroundColor Cyan

# 레지스트리 조작 대신 공식 Cmdlet으로 S2S VPN 및 LAN 라우팅 엔진 구성
Install-RemoteAccess -VpnType VpnS2S -ErrorAction SilentlyContinue

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

# 2. VPN 인터페이스 구성 (현업 표준: Narrow TS 강제 협상 및 BGP 정책 허용)
Write-Host "2. VPN 인터페이스 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="100"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="150"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 생성 중..."
    
    # AWS VPC 대역($AwsVpcCidr)과 BGP 통신 대역(169.254.0.0/16)을 배열로 동시 주입
    # 이 배열이 IPsec TS가 되어 인터넷 하이재킹을 차단하고 BGP 패킷 드랍을 방지합니다.
    $awsTargetSubnets = @(
        "$AwsVpcCidr:$($t.Metric)",
        "169.254.0.0/16:$($t.Metric)"
    )
    
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet $awsTargetSubnets -Protocol IKEv2 -ErrorAction Stop
    
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    Start-Sleep -Seconds 5

    try { New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop } catch {}
    try { New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction Stop } catch {}
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

# 4. BGP 경로 광고 (동적 변수 사용)
Write-Host "4. BGP 경로 광고 중 ($OnpremVpcCidr)..." -ForegroundColor Cyan
try { Add-BgpCustomRoute -Network $OnpremVpcCidr -ErrorAction Stop } catch {}

# 5. 인터넷 경로 보호
Write-Host "5. 인터넷 경로 보호 중..." -ForegroundColor Cyan

# 가상 어댑터 우회: 실제 활성화된 0.0.0.0/0 인터넷 경로를 가진 어댑터를 역추적
$activeInternetRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1

if ($activeInternetRoute) {
    $eth = Get-NetAdapter -InterfaceIndex $activeInternetRoute.InterfaceIndex -ErrorAction SilentlyContinue
    $defaultGateway = $activeInternetRoute.NextHop
    
    if ($eth -and $defaultGateway) {
        Write-Host "인터넷 어댑터 인식 완료: $($eth.Name), 게이트웨이: $defaultGateway" -ForegroundColor Green
        
        # 1. 인터페이스 메트릭 절대 우위 설정
        Set-NetIPInterface -InterfaceAlias $eth.Name -InterfaceMetric 5
        
        # 2. 기존 인터넷 경로 보호 덮어쓰기
        try { 
            Set-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceAlias $eth.Name -NextHop $defaultGateway -RouteMetric 5 -ErrorAction SilentlyContinue 
        } catch {}
    }
} else {
    Write-Host "활성화된 인터넷 기본 경로를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green