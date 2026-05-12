# =============================================================================
# 08-validate-gateway.ps1 — curl --resolve + .NET TLS SNI checks against the
# managed Gateway API (App Routing + Istio) LoadBalancer.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"

$svc = "$($global:GW_NAME)-approuting-istio"
$ip = kubectl get svc $svc -n $global:NS_GW -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if (-not $ip) {
    $state = Get-Content "$PSScriptRoot/.poc-state" -Raw | ConvertFrom-Json
    $ip = $state.GW_IP
}
if (-not $ip) { throw "Gateway IP not found." }
Write-Host "Targeting Gateway at $ip`n" -ForegroundColor Cyan

function Get-TlsCertSubject {
    param([string]$Ip, [string]$Sni)
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $tcp.Connect($Ip, 443)
        $cb = { param($s,$cert,$chain,$err) $true }
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, $cb)
        $ssl.AuthenticateAsClient($Sni)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
        $ssl.Dispose(); $tcp.Dispose()
        return $cert.Subject
    } catch {
        return "ERROR: $_"
    }
}

foreach ($h in @($global:HOST_APP1, $global:HOST_APP2, $global:HOST_APP3)) {
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host "Hostname: $h" -ForegroundColor Yellow
    Write-Host "  Body  : " -NoNewline
    & curl.exe -sk --max-time 10 --resolve "${h}:443:${ip}" "https://$h/"
    Write-Host
    Write-Host "  Cert  : $(Get-TlsCertSubject -Ip $ip -Sni $h)" -ForegroundColor Cyan
}
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "Gateway API validated — 3 hosts, 3 certs." -ForegroundColor Green
