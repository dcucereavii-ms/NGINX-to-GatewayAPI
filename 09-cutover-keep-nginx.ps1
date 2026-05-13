# =============================================================================
# 09-cutover-keep-nginx.ps1
#
# Logical cutover: declare the Gateway the "primary" entry point, but KEEP
# NGINX running and intact as a fallback / reference.
#
# What this script does:
#   1. Verifies both stacks are healthy (NGINX + Gateway).
#   2. Side-by-side validation: same 3 hosts against both LB IPs.
#   3. Compares response body + TLS cert subject from each path.
#   4. Prints a hosts-file snippet for manual client cutover testing.
#   5. Does NOT delete anything. NGINX stays as a parallel reference.
#
# Real production cutover is a DNS change — this script gives you the data
# you need to confidently make that change one hostname at a time.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"

# Load .poc-state (key=value lines) into a hashtable
$state = @{}
if (Test-Path "$PSScriptRoot/.poc-state") {
    Get-Content "$PSScriptRoot/.poc-state" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
}

# Refresh IPs from the cluster (state file is best-effort)
$nginxIp = kubectl get svc -n ingress-nginx ingress-nginx-controller `
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if (-not $nginxIp) { $nginxIp = $state['NGINX_IP'] }

$gwSvc = "$($global:GW_NAME)-approuting-istio"
$gwIp = kubectl get svc -n $global:NS_GW $gwSvc `
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if (-not $gwIp) { $gwIp = $state['GW_IP'] }

if (-not $nginxIp -or -not $gwIp) {
    throw "Could not resolve both NGINX ($nginxIp) and Gateway ($gwIp) IPs."
}

Write-Host ""
Write-Host "==> Both stacks online" -ForegroundColor Cyan
Write-Host ("  NGINX  : {0}" -f $nginxIp) -ForegroundColor Gray
Write-Host ("  Gateway: {0}" -f $gwIp)    -ForegroundColor Gray
Write-Host ""

function Get-Probe {
    param([string]$Ip, [string]$HostName)
    $body = & curl.exe -sk --max-time 8 --resolve "${HostName}:443:${Ip}" "https://$HostName/"
    $subj = "n/a"
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new(); $tcp.Connect($Ip, 443)
        $cb = { param($s,$c,$ch,$e) $true }
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, $cb)
        $ssl.AuthenticateAsClient($HostName)
        $subj = ([System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    $ssl.RemoteCertificate)).Subject
        $ssl.Dispose(); $tcp.Dispose()
    } catch {}
    return [pscustomobject]@{ Body = ($body | Out-String).Trim(); Cert = $subj }
}

$results = foreach ($h in @($global:HOST_APP1, $global:HOST_APP2, $global:HOST_APP3)) {
    $n = Get-Probe -Ip $nginxIp -HostName $h
    $g = Get-Probe -Ip $gwIp    -HostName $h
    [pscustomobject]@{
        Host        = $h
        NGINX_Body  = $n.Body
        GW_Body     = $g.Body
        NGINX_Cert  = $n.Cert
        GW_Cert     = $g.Cert
        BodyMatch   = ($n.Body -eq $g.Body)
        CertMatch   = ($n.Cert -eq $g.Cert)
    }
}

$results | Format-Table Host,BodyMatch,CertMatch,NGINX_Cert,GW_Cert -AutoSize
Write-Host ""
foreach ($r in $results) {
    $status = if ($r.BodyMatch -and $r.CertMatch) { "PARITY OK" } else { "MISMATCH" }
    $color  = if ($r.BodyMatch -and $r.CertMatch) { "Green" }     else { "Red" }
    Write-Host ("  {0,-30} {1}" -f $r.Host, $status) -ForegroundColor $color
    Write-Host ("      NGINX body : {0}" -f $r.NGINX_Body) -ForegroundColor DarkGray
    Write-Host ("      GW    body : {0}" -f $r.GW_Body)    -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "==> Cutover guidance" -ForegroundColor Cyan
Write-Host "  Production : update DNS A records one host at a time:" -ForegroundColor Gray
foreach ($h in @($global:HOST_APP1, $global:HOST_APP2, $global:HOST_APP3)) {
    Write-Host ("    {0,-30}  {1}  -->  {2}" -f $h, $nginxIp, $gwIp) -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Local test : add to C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Gray
Write-Host "               (Run Notepad as Administrator):" -ForegroundColor Gray
Write-Host ""
foreach ($h in @($global:HOST_APP1, $global:HOST_APP2, $global:HOST_APP3)) {
    Write-Host ("    {0}    {1}" -f $gwIp, $h) -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Rollback   : flip DNS / hosts entry back to $nginxIp" -ForegroundColor Gray
Write-Host ""
Write-Host "==> NGINX kept as reference. To decommission later:" -ForegroundColor Cyan
Write-Host "    .\09b-decommission-nginx.ps1" -ForegroundColor Gray
Write-Host ""
$allOk = ($results | Where-Object { -not ($_.BodyMatch -and $_.CertMatch) }).Count -eq 0
if ($allOk) {
    Write-Host "✅ Both stacks are at parity. Safe to flip DNS to $gwIp." -ForegroundColor Green
} else {
    Write-Host "⚠ Mismatch detected — investigate before cutover." -ForegroundColor Red
}
