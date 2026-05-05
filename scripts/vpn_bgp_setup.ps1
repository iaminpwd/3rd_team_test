$ErrorActionPreference = "Stop"

Write-Host "1. 서비스 종속성 복구 및 RRAS 강제 초기화" -ForegroundColor Cyan

# 1-1. RasMan이 죽는 근본 원인: 종속 서비스(Telephony, SSTP) 강제 활성화
$dependencies = @("TapiSrv", "SstpSvc", "nsi")
foreach ($dep in $dependencies) {
    Write-Host "[$dep] 서비스 복구 중..."
    Set-Service $dep -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service $dep -ErrorAction SilentlyContinue
}

# 1-2. 핵심 엔진 서비스(RasMan, RemoteAccess) 초기화
$coreServices = @("RasMan", "RemoteAccess")
foreach ($svc in $coreServices) {
    Set-Service $svc -StartupType Automatic -ErrorAction SilentlyContinue
}

# 1-3. [중요] 기존에 꼬여있던 라우팅 구성을 완전히 날리고 새로 배포
Write-Host "RRAS 엔진 재구성 중 (Install-RemoteAccess)..." -ForegroundColor Cyan
Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue
Install-RemoteAccess -VpnType RoutingOnly -ErrorAction SilentlyContinue

# 1-4. 엔진 시동 및 안정화 대기
Start-Service RasMan -ErrorAction SilentlyContinue
Start-Service RemoteAccess -ErrorAction SilentlyContinue

Write-Host "VPN 엔진 초기화 대기 중... (최대 3분)" -ForegroundColor Cyan
$retryCount = 0
$rrasReady = $false

while (-not $rrasReady -and $retryCount -lt 36) {
    try {
        # 엔진이 실제로 명령어를 받을 수 있는지 테스트
        $null = Get-VpnS2SInterface -ErrorAction Stop
        $rrasReady = $true
        Write-Host "✅ 엔진 복구 성공! 정상 작동합니다." -ForegroundColor Green
    } catch {
        $retryCount++
        # 서비스가 죽어있다면 다시 한번 살려봄
        Start-Service RasMan -ErrorAction SilentlyContinue
        Start-Service RemoteAccess -ErrorAction SilentlyContinue
        Write-Host "엔진 응답 대기 중... ($retryCount/36)"
        Start-Sleep -Seconds 5
    }
}

if (-not $rrasReady) {
    throw "RRAS 엔진 복구 실패. 이 서버의 윈도우 네트워크 스택에 치명적 결함이 있습니다."
}

Write-Host "2. VPN 인터페이스 구성 및 업데이트" -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10" },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50" }
)
foreach ($t in $tunnels) {
    $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
    if ($null -eq $iface) {
        Write-Host "[$($t.Name)] 생성 중..."
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2
    } elseif ($iface.Destination -ne $t.Dest) {
        Write-Host "[$($t.Name)] 업데이트 중..."
        Set-VpnS2SInterface -Name $t.Name -Destination $t.Dest -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)"
    }
}

Write-Host "3. BGP 라우터 및 Peer 구성" -ForegroundColor Cyan
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

Write-Host "4. BGP 경로 광고 및 트래픽 제어" -ForegroundColor Cyan
Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue
Get-BgpRoutingPolicy -ErrorAction SilentlyContinue | Remove-BgpRoutingPolicy -Force -ErrorAction SilentlyContinue

$ip = $OnpremVpcCidr.Split("/")[0]
$net1 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).0/25"
$net2 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).128/25"

Add-BgpCustomRoute -Network $net1, $net2 -ErrorAction SilentlyContinue
Add-BgpRoutingPolicy -Name "DenySplitOnTunnel2" -PolicyType Deny -MatchPrefix $net1, $net2 -ErrorAction SilentlyContinue
Set-BgpRoutingPolicyForPeer -PeerName "AWS-TGW-Peer2" -PolicyName "DenySplitOnTunnel2" -Direction Egress -Force

Restart-Service RemoteAccess
Write-Host "✅ 하이브리드 인프라 구성이 완벽하게 완료되었습니다!" -ForegroundColor Green