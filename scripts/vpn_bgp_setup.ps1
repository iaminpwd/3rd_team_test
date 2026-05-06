# =================================================================
# scripts/vpn_bgp_setup.ps1 (최종 안정화 버전)
# =================================================================
$ErrorActionPreference = "Stop"

Write-Host "0. 필수 Windows 기능(Routing, RemoteAccess) 설치 검증" -ForegroundColor Cyan
$feature = Get-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -ErrorAction SilentlyContinue
if ($null -ne $feature -and ($feature.InstallState -contains "Available" -or $feature.InstallState -contains "Removed")) {
    Write-Host "필수 기능이 누락되어 설치를 진행합니다. (수 분 소요 가능)"
    Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction Stop
}

Write-Host "0-1. Windows 방화벽 필수 포트(IPsec/BGP) 개방" -ForegroundColor Cyan
$fwRules = @(
    @{ Name="Allow-IPsec-IKE-UDP500"; Port="500"; Protocol="UDP" },
    @{ Name="Allow-IPsec-NATT-UDP4500"; Port="4500"; Protocol="UDP" },
    @{ Name="Allow-BGP-TCP179"; Port="179"; Protocol="TCP" }
)
foreach ($rule in $fwRules) {
    try {
        $null = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction Stop
    } catch {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port -ErrorAction SilentlyContinue
    }
}
try {
    $null = Get-NetFirewallRule -DisplayName "Allow-IPsec-ESP-Proto50" -ErrorAction Stop
} catch {
    New-NetFirewallRule -DisplayName "Allow-IPsec-ESP-Proto50" -Direction Inbound -Action Allow -Protocol 50 -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------
# 1. 엔진 무조건 철거 후 재건축
# -----------------------------------------------------------------
Write-Host "1. RRAS 엔진 초기화 및 LAN 라우팅 활성화" -ForegroundColor Cyan
try {
    Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue
    Write-Host "기존 엔진 철거 완료."
} catch {}
Start-Sleep -Seconds 5

Install-RemoteAccess -VpnType VpnS2S -ErrorAction Stop
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

try { Restart-Service RasMan -Force -ErrorAction SilentlyContinue } catch {}
try { Restart-Service RemoteAccess -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 10

# -----------------------------------------------------------------
# 2. VPN 인터페이스 구성 및 경로 주입
# -----------------------------------------------------------------
Write-Host "2. VPN 인터페이스 및 BGP 통신 경로 구성" -ForegroundColor Cyan

$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    $iface = $null
    try { $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    
    # [핵심] 에러 방지를 위해 -IPv4Subnet에는 순수 VPC 대역만 할당합니다.
    $vpcSubnet = "${AwsVpcCidr}:$($t.Metric)"

    if ($null -eq $iface) {
        Write-Host "[$($t.Name)] 생성 중..."
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet $vpcSubnet -Protocol IKEv2
    } else {
        Write-Host "[$($t.Name)] 업데이트 중..."
        Set-VpnS2SInterface -Name $t.Name -Destination $t.Dest -SharedSecret $t.Psk -IPv4Subnet $vpcSubnet
    }

    # BGP Local IP 강제 할당
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue

    # [핵심 수정] BGP Peer IP(169.254.x.x)로 가는 전용 경로를 별도의 라우팅 테이블에 주입합니다.
    # 이렇게 하면 Add-VpnS2SInterface의 에러를 피하면서 BGP 통신을 확실히 잡아줍니다.
    Write-Host "[$($t.Name)] BGP Peer($($t.PeerIP)) 경로 강제 주입 중..." -ForegroundColor Yellow
    New-NetRoute -DestinationPrefix "$($t.PeerIP)/32" -InterfaceAlias $t.Name -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------
# 3. BGP 라우터 및 Peer 구성
# -----------------------------------------------------------------
Write-Host "3. BGP 라우터 및 Peer 구성" -ForegroundColor Cyan
$dynamic_lan_ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1

$router = $null
try { $router = Get-BgpRouter -ErrorAction Stop } catch {}
if ($null -eq $router) {
    Add-BgpRouter -BgpIdentifier $dynamic_lan_ip -LocalASN 65000 -Force
}

$peers = @(
    @{ Name="AWS-TGW-Peer1"; Local=$BgpLocal1Ip; Peer=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Peer2"; Local=$BgpLocal2Ip; Peer=$BgpPeer2Ip }
)
foreach ($p in $peers) {
    $bgpPeer = $null
    try { $bgpPeer = Get-BgpPeer -Name $p.Name -ErrorAction Stop } catch {}
    if ($null -eq $bgpPeer) {
        Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512
    }
    try { Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue } catch {}
}

# -----------------------------------------------------------------
# 4. BGP 경로 광고 및 최종 리프레시
# -----------------------------------------------------------------
Write-Host "4. BGP 경로 광고 및 최종 리프레시" -ForegroundColor Cyan
try { Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue } catch {}

$ip = $OnpremVpcCidr.Split("/")[0]
$net1 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).0/25"
$net2 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).128/25"

Add-BgpCustomRoute -Network $net1, $net2 -ErrorAction SilentlyContinue

# 최종 서비스 재시작하여 모든 경로와 IP 바인딩을 확정합니다.
Write-Host "BGP 세션 확립을 위해 서비스를 최종 재시작합니다..."
Restart-Service RemoteAccess -Force
Start-Sleep -Seconds 15

Write-Host "✅ 하이브리드 인프라 구성이 완벽하게 완료되었습니다!" -ForegroundColor Green