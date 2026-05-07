# =================================================================
# scripts/vpn_bgp_setup.ps1 (하드코딩 복구 및 경로 보호 포함)
# =================================================================
$ErrorActionPreference = "Stop"

# [직접 입력] 변수 주입 대신 하드코딩으로 설정
$AwsVpcCidr = "10.0.0.0/16"
$OnpremVpcCidr = "192.168.0.0/24"

# 0. 필수 기능 및 방화벽 설정
Write-Host "0. 필수 기능 및 방화벽 설정 중..." -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction SilentlyContinue

# 1. RRAS 라우팅 엔진 안전 기동 및 초기화
Write-Host "1. RRAS 라우팅 엔진 안전 기동 및 초기화 중..." -ForegroundColor Cyan
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
try { Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force } catch {}

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

# 2. VPN 인터페이스 구성 (Metric을 높여 인터넷 하이재킹 방지)
Write-Host "2. VPN 인터페이스 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="100"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="150"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 생성 중..."
    # 하드코딩된 $AwsVpcCidr 대신 0.0.0.0/0을 열어 확장성 유지
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "0.0.0.0/0:$($t.Metric)" -Protocol IKEv2 -ErrorAction Stop
    
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

# 5. 인터넷 경로 보호 (서열 정리)
Write-Host "5. 인터넷 경로 보호 중..." -ForegroundColor Cyan
$eth = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
if ($eth) {
    Set-NetIPInterface -InterfaceAlias $eth.Name -InterfaceMetric 10
    route add 0.0.0.0 mask 0.0.0.0 192.168.0.1 metric 10 if (Get-NetAdapter -Name $eth.Name).InterfaceIndex
}

Write-Host "✅ 모든 설정 완료!" -ForegroundColor Green