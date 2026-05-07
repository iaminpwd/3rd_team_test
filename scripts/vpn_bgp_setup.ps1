# =================================================================
# scripts/vpn_bgp_setup.ps1 (하드코딩 복구 및 경로 보호 포함)
# =================================================================
$ErrorActionPreference = "Stop"


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

# 2. VPN 인터페이스 구성 (Split Tunneling - 타겟 AWS VPC 대역만 정확히 라우팅)
Write-Host "2. VPN 인터페이스 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="100"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="150"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 생성 중..."
    
    # [수정됨] 0.0.0.0/0 이나 잘못된 사설망 전체가 아닌, 주입받은 정확한 AWS 대상 대역($AwsVpcCidr)만 VPN으로 넘김
    $awsTargetSubnet = "$AwsVpcCidr:$($t.Metric)"
    
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet $awsTargetSubnet -Protocol IKEv2 -ErrorAction Stop
    
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    Start-Sleep -Seconds 5

    try { New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop } catch {}
    try { New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction Stop } catch {}
}

# 3. BGP 라우터 및 Peer 구성
Write-Host "3. BGP 설정 중..." -ForegroundColor Cyan
$myIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1

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

# 4. BGP 경로 광고 (하드코딩된 변수 사용)
Write-Host "4. BGP 경로 광고 중 ($OnpremVpcCidr)..." -ForegroundColor Cyan
try { Add-BgpCustomRoute -Network $OnpremVpcCidr -ErrorAction Stop } catch {}

# 5. 인터넷 경로 보호
Write-Host "5. 인터넷 경로 보호 중..." -ForegroundColor Cyan
# 상태가 Up인 실제 물리/가상 이더넷 어댑터 탐색
$eth = Get-NetAdapter | Where-Object Status -eq "Up" | Where-Object Name -NotMatch "Tunnel" | Select-Object -First 1

if ($eth) {
    # 1. 인터페이스 메트릭 조정
    Set-NetIPInterface -InterfaceAlias $eth.Name -InterfaceMetric 10
    
    # 2. 동적으로 기본 게이트웨이 IP 추출 (하드코딩 192.168.0.1 제거)
    $defaultGateway = (Get-NetIPConfiguration -InterfaceAlias $eth.Name).IPv4DefaultGateway.NextHop
    
    if ($defaultGateway) {
        # 3. 파워쉘 네이티브 명령어로 멱등성 보장 라우팅 추가
        try { 
            New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceAlias $eth.Name -NextHop $defaultGateway -RouteMetric 10 -ErrorAction Stop 
        } catch {
            Write-Host "기본 경로가 이미 존재하거나 설정할 수 없습니다. (정상)" -ForegroundColor Gray
        }
    }
}