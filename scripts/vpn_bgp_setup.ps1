# $ErrorActionPreference = "Stop" 을 선언하여 에러 발생 시 즉시 중단 (Fail-Fast)
$ErrorActionPreference = "Stop"

# 파이프라인에서 주입받을 매개변수 (파라미터화)
param (
    [string]$AwsVpcCidr,
    [string]$OnpremVpcCidr,
    [string]$Tunnel1Ip,
    [string]$Tunnel1Psk,
    [string]$Tunnel2Ip,
    [string]$Tunnel2Psk,
    [string]$BgpLocal1Ip,
    [string]$BgpPeer1Ip,
    [string]$BgpLocal2Ip,
    [string]$BgpPeer2Ip
)

Write-Host "1. RRAS(Routing) 기능 설치 및 확인"
$rras = Get-WindowsFeature Routing
if ($rras.InstallState -ne "Installed") {
    Install-WindowsFeature Routing -IncludeManagementTools
    Start-Service RemoteAccess
}

Write-Host "2. VPN 인터페이스 구성 (Active/Standby)"
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10" },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50" }
)
foreach ($t in $tunnels) {
    $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
    if ($null -eq $iface) {
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "$AwsVpcCidr:$($t.Metric)" -Protocol IKEv2
    }
}

Write-Host "3. BGP 라우터 및 Peer 구성"
$dynamic_lan_ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
$router = Get-BgpRouter -ErrorAction SilentlyContinue
if ($null -eq $router) {
    Add-BgpRouter -BgpIdentifier $dynamic_lan_ip -LocalASN 65000 -Force
}

Add-BgpPeer -Name "AWS-TGW-Peer1" -LocalIPAddress $BgpLocal1Ip -PeerIPAddress $BgpPeer1Ip -PeerASN 64512 -ErrorAction SilentlyContinue
Add-BgpPeer -Name "AWS-TGW-Peer2" -LocalIPAddress $BgpLocal2Ip -PeerIPAddress $BgpPeer2Ip -PeerASN 64512 -ErrorAction SilentlyContinue

Write-Host "모든 구성이 성공적으로 완료되었습니다."