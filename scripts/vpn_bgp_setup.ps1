$ErrorActionPreference = "Stop"

Write-Host "1. RRAS(Routing) 기능 설치 및 확인"
$rras = Get-WindowsFeature Routing
if ($rras.InstallState -ne "Installed") {
    Install-WindowsFeature Routing -IncludeManagementTools
}
Start-Service RemoteAccess -ErrorAction SilentlyContinue

Write-Host "2. VPN 인터페이스 구성 (Active/Standby)"
$tunnels = @(
    @{ Name="AWS-TGW-Tunnel1"; Dest=$Tunnel1Ip; Psk=$Tunnel1Psk; Metric="10" },
    @{ Name="AWS-TGW-Tunnel2"; Dest=$Tunnel2Ip; Psk=$Tunnel2Psk; Metric="50" }
)
foreach ($t in $tunnels) {
    $iface = Get-VpnS2SInterface -Name $t.Name -ErrorAction SilentlyContinue
    if ($null -eq $iface) {
        Add-VpnS2SInterface -Name $t.Name -Destination $t.Dest -AuthenticationMethod PSKOnly -SharedSecret $t.Psk -IPv4Subnet "${AwsVpcCidr}:$($t.Metric)" -Protocol IKEv2
    } elseif ($iface.Destination -ne $t.Dest) {
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

Write-Host "4. BGP 경로 광고 및 우선순위 정책 적용"
Get-BgpCustomRoute -ErrorAction SilentlyContinue | Remove-BgpCustomRoute -Force -ErrorAction SilentlyContinue
Get-BgpRoutingPolicy -ErrorAction SilentlyContinue | Remove-BgpRoutingPolicy -Force -ErrorAction SilentlyContinue

$ip = $OnpremVpcCidr.Split("/")[0]
$net1 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).0/25"
$net2 = "$($ip.Split('.')[0]).$($ip.Split('.')[1]).$($ip.Split('.')[2]).128/25"

Add-BgpCustomRoute -Network $net1, $net2 -ErrorAction SilentlyContinue
Add-BgpRoutingPolicy -Name "DenySplitOnTunnel2" -PolicyType Deny -MatchPrefix $net1, $net2 -ErrorAction SilentlyContinue
Set-BgpRoutingPolicyForPeer -PeerName "AWS-TGW-Peer2" -PolicyName "DenySplitOnTunnel2" -Direction Egress -Force

Restart-Service RemoteAccess
Write-Host "모든 구성이 성공적으로 완료되었습니다."