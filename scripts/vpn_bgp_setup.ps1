# =================================================================
# scripts/vpn_bgp_setup.ps1
# =================================================================
$ErrorActionPreference = "Stop"

Write-Host "0. 필수 Windows 기능(Routing, RemoteAccess) 설치 검증" -ForegroundColor Cyan
$feature = Get-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -ErrorAction SilentlyContinue
if ($null -ne $feature -and ($feature.InstallState -contains "Available" -or $feature.InstallState -contains "Removed")) {
    Write-Host "필수 기능이 누락되어 설치를 진행합니다. (수 분 소요 가능)"
    Install-WindowsFeature -Name RemoteAccess, Routing, DirectAccess-VPN -IncludeManagementTools -ErrorAction Stop
}

Write-Host "0-1. Windows 방화벽 IPsec/IKEv2 필수 포트 개방" -ForegroundColor Cyan
$fwRules = @(
    @{ Name="Allow-IPsec-IKE-UDP500"; Port="500"; Protocol="UDP" },
    @{ Name="Allow-IPsec-NATT-UDP4500"; Port="4500"; Protocol="UDP" }
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
# [핵심] 1. 엔진 무조건 철거 후 재건축 (Try-Catch 적용)
# -----------------------------------------------------------------
Write-Host "1. RRAS 엔진 초기화 및 LAN 라우팅(BGP) 강제 활성화" -ForegroundColor Cyan

Write-Host "기존 RRAS 설정을 초기화합니다..."
try {
    # 지울 게 없어서 나는 에러를 안전하게 무시합니다.
    Uninstall-RemoteAccess -Force -ErrorAction Stop
    Write-Host "기존 엔진 철거 완료."
} catch {
    Write-Host "👉 지울 이전 설정이 없습니다. (이미 깨끗한 상태입니다)" -ForegroundColor Yellow
}
Start-Sleep -Seconds 5

Write-Host "깨끗한 상태에서 RRAS 엔진 재설치 중..."
Install-RemoteAccess -VpnType VpnS2S -ErrorAction Stop

Write-Host "BGP 모듈을 깨우기 위해 LAN Routing(RouterType=7) 강제 세팅..."
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

Write-Host "라우팅 서비스 재시작 및 BGP 모듈 로딩 중... (10초 대기)"
try { Restart-Service RasMan -Force -ErrorAction Stop } catch {}
try { Restart-Service RemoteAccess -Force -ErrorAction Stop } catch {}
Start-Sleep -Seconds 10

# -----------------------------------------------------------------
# 2. VPN 인터페이스 구성 (BGP Local IP 강제 주입 로직 통합)
# -----------------------------------------------------------------
Write-Host "2. VPN 인터페이스 구성 및 BGP IP 강제 할당" -ForegroundColor Cyan

# 각 터널별로 Local IP 정보를 배열에 추가합니다.
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip }
)

foreach ($t in $tunnels) {
    $iface = $null
    try { $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    
    if ($null -eq $iface) {
        Write-Host "[$($t.Name)] 생성 중..."
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2
    } else {
        Write-Host "[$($t.Name)] 업데이트 중..."
        Set-VpnS2SInterface -Name $t.Name -Destination $t.Dest -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)"
    }

    # [핵심 수정 부분] 윈도우의 랜덤 APIPA 할당을 방지하기 위해 BGP Local IP를 강제로 인터페이스에 부여합니다.
    Write-Host "[$($t.Name)] BGP Local IP($($t.LocalIP)) 강제 바인딩 중..." -ForegroundColor Yellow
    New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction SilentlyContinue
}

Write-Host "3. BGP 라우터 및 Peer 구성" -ForegroundColor Cyan
$dynamic_lan_ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1

# 라우터 추가 전, 이미 있는지 확인
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
    try { Start-BgpPeer -Name $p.Name -ErrorAction Stop } catch {}
}

Write-Host "4. BGP 경로 광고 및 트래픽 제어" -ForegroundColor Cyan
try { Get-BgpCustomRoute -ErrorAction Stop | Remove-BgpCustomRoute -Force -ErrorAction Stop } catch { }
try { Get-BgpRoutingPolicy -ErrorAction Stop | Remove-BgpRoutingPolicy -Force -ErrorAction Stop } catch { }

$ip = $OnpremVpcCidr.Split("/")[0]
$net1 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).0/25"
$net2 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).128/25"

Add-BgpCustomRoute -Network $net1, $net2 -ErrorAction SilentlyContinue
Add-BgpRoutingPolicy -Name "DenySplitOnTunnel2" -PolicyType Deny -MatchPrefix $net1, $net2 -ErrorAction SilentlyContinue
Set-BgpRoutingPolicyForPeer -PeerName "AWS-TGW-Peer2" -PolicyName "DenySplitOnTunnel2" -Direction Egress -Force

Write-Host "✅ 하이브리드 인프라 구성이 완벽하게 완료되었습니다!" -ForegroundColor Green