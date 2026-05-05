$ErrorActionPreference = "Stop"

Write-Host "1. RRAS(Routing) 기능 설치 및 서비스 초기화"
$rras = Get-WindowsFeature Routing
if ($rras.InstallState -ne "Installed") {
    Install-WindowsFeature Routing -IncludeManagementTools
}

# 라우팅 전용 모드로 RRAS 초기 구성
Install-RemoteAccess -VpnType RoutingOnly -ErrorAction SilentlyContinue

# 서비스 자동 시작 설정 및 강제 실행
Set-Service RemoteAccess -StartupType Automatic -ErrorAction SilentlyContinue
if ((Get-Service RemoteAccess).Status -ne 'Running') {
    Start-Service RemoteAccess
}

# ====================================================================
# [핵심 수정] RRAS VPN 엔진이 완전히 준비될 때까지 기다리는 폴링(Polling) 로직
# ====================================================================
Write-Host "RRAS 내부 VPN 엔진 초기화 대기 중... (최대 60초)"
$retryCount = 0
$rrasReady = $false

while (-not $rrasReady -and $retryCount -lt 12) {
    try {
        # 엔진이 깨어났는지 확인하기 위해 더미 조회를 날려봅니다.
        # 에러 없이 통과하면 엔진이 준비된 것입니다.
        $null = Get-VpnS2SInterface -ErrorAction Stop
        $rrasReady = $true
        Write-Host "✅ RRAS 엔진 준비 완료!"
    } catch {
        $retryCount++
        Write-Host "엔진 부팅 중... 5초 대기 ($retryCount/12)"
        Start-Sleep -Seconds 5
    }
}

if (-not $rrasReady) {
    throw "RRAS 엔진이 시간 내에 초기화되지 않았습니다. 윈도우 서버 재부팅이 필요할 수 있습니다."
}
# ====================================================================


Write-Host "2. VPN 인터페이스 구성 및 업데이트"
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10" },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50" }
)
foreach ($t in $tunnels) {
    # 이제 엔진이 깨어있으므로 에러 없이 안전하게 조회됩니다.
    $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
    
    if ($null -eq $iface) {
        Write-Host "[$($t.Name)] 생성 중..."
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2
    } elseif ($iface.Destination -ne $t.Dest) {
        Write-Host "[$($t.Name)] 업데이트 중..."
        Set-VpnS2SInterface -Name $t.Name -Destination $t.Dest -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)"
    }
}


Write-Host "3. BGP 라우터 및 Peer 구성"
$dynamic_lan_ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
$router = Get-BgpRouter -ErrorAction SilentlyContinue
if ($null -eq $router) {
    Add-BgpRouter -BgpIdentifier $dynamic_lan_ip -LocalASN 65000 -Force
}

$peers = @(
    @{ Name="AWS-TGW-Peer1"; Local=$BgpLocal1Ip; Peer=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Peer2"; Local=$BgpLocal2Ip; Peer=$BgpPeer2Ip }
)
foreach ($p in $peers) {
    $bgpPeer = Get-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue
    if ($null -eq $bgpPeer) {
        Add-BgpPeer -Name $p.Name -LocalIPAddress $p.Local -PeerIPAddress $p.Peer -PeerASN 64512
    }
    Start-BgpPeer -Name $p.Name -ErrorAction SilentlyContinue
}


Write-Host "4. BGP 경로 광고 및 트래픽 제어"
Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue
Get-BgpRoutingPolicy -ErrorAction SilentlyContinue | Remove-BgpRoutingPolicy -Force -ErrorAction SilentlyContinue

$ip = $OnpremVpcCidr.Split("/")[0]
$net1 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).0/25"
$net2 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).128/25"

Add-BgpCustomRoute -Network $net1, $net2 -ErrorAction SilentlyContinue
Add-BgpRoutingPolicy -Name "DenySplitOnTunnel2" -PolicyType Deny -MatchPrefix $net1, $net2 -ErrorAction SilentlyContinue
Set-BgpRoutingPolicyForPeer -PeerName "AWS-TGW-Peer2" -PolicyName "DenySplitOnTunnel2" -Direction Egress -Force

Restart-Service RemoteAccess
Write-Host "✅ 모든 구성이 성공적으로 완료되었습니다."