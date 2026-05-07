# =================================================================
# scripts/vpn_bgp_setup.ps1 (Ghost 어댑터 문제 해결 최종본)
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

# 1. RRAS 엔진 무조건 철거 후 재건축 중... (보강된 코드)
Write-Host "1. RRAS 엔진 무조건 철거 후 재건축 중..." -ForegroundColor Cyan

try { Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 10  # 삭제 후 윈도우가 정리할 시간을 줍니다.

Install-RemoteAccess -VpnType VpnS2S -ErrorAction Stop

# 레지스트리 설정
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters"
Set-ItemProperty -Path $regPath -Name "RouterType" -Value 7 -Force

Write-Host "라우팅 서비스 안전 재시작 및 엔진 활성화 대기..." -ForegroundColor Yellow
Restart-Service RemoteAccess -Force

# [핵심] 서비스가 Running인 것만으로는 부족합니다. 
# 관리 명령(Get-RemoteAccess)이 실제로 응답할 때까지 최대 2분을 기다립니다.
$retryCount = 0
while ($retryCount -lt 12) {
    try {
        $status = Get-RemoteAccess -ErrorAction Stop
        Write-Host "▶ 라우팅 엔진이 명령을 받을 준비가 되었습니다!" -ForegroundColor Green
        break
    } catch {
        Write-Host "⏳ 엔진 초기화 대기 중... ($($retryCount * 10)초 경과)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
        $retryCount++
    }
}

if ($retryCount -eq 12) {
    throw "오류: 윈도우 라우팅 엔진이 너무 오래 응답하지 않습니다. 서버 재부팅이 필요할 수 있습니다."
}
Write-Host "▶ 라우팅 엔진 가동 완료!" -ForegroundColor Green

# 2. VPN 인터페이스 및 라우팅 구성 (순서 교정 완료)
Write-Host "2. VPN 인터페이스 및 경로 구성 중..." -ForegroundColor Cyan
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10"; LocalIP=$BgpLocal1Ip; PeerIP=$BgpPeer1Ip },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50"; LocalIP=$BgpLocal2Ip; PeerIP=$BgpPeer2Ip }
)

foreach ($t in $tunnels) {
    Write-Host "[$($t.Name)] 인터페이스 생성 중..."
    # 수정 후 (완벽본)
    Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "0.0.0.0/0:$($t.Metric)" -Protocol IKEv2 -ErrorAction Stop
    
    # [핵심] IP를 넣기 전에 터널을 먼저 연결하여 유령 어댑터를 OS에 실체화시킵니다.
    Write-Host "[$($t.Name)] 어댑터 활성화를 위한 터널 강제 연결 트리거..." -ForegroundColor Yellow
    try { Connect-VpnS2SInterface -Name $t.Name -ErrorAction Stop } catch {}
    
    # 어댑터가 OS에 완전히 등록될 때까지 충분히 대기합니다. (매우 중요)
    Start-Sleep -Seconds 5

    Write-Host "[$($t.Name)] 활성화된 어댑터에 BGP용 로컬 IP 바인딩 중..."
    try {
        Get-NetIPAddress -InterfaceAlias $t.Name -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -ne $t.LocalIP } | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
    } catch {}
    
    # 이제 어댑터가 존재하므로 Element not found 에러가 발생하지 않습니다.
    try { New-NetIPAddress -InterfaceAlias $t.Name -IPAddress $t.LocalIP -PrefixLength 30 -AddressFamily IPv4 -ErrorAction Stop } catch {}
    
    # BGP 목적지(Peer IP) 라우팅 삽입
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