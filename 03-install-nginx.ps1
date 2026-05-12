# =============================================================================
# 03-install-nginx.ps1  —  Helm install ingress-nginx
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null

Write-Host "==> Installing ingress-nginx" -ForegroundColor Green
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    --set controller.service.externalTrafficPolicy=Local `
    --set controller.replicaCount=2 | Out-Null

Write-Host "`n==> Waiting for LoadBalancer IP..." -ForegroundColor Green
$ip = $null
for ($i = 0; $i -lt 60; $i++) {
    $ip = kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ip) { break }
    Start-Sleep -Seconds 5
}
if (-not $ip) { throw "NGINX LoadBalancer IP not assigned in time." }

"NGINX_IP=$ip" | Add-Content "$PSScriptRoot/.poc-state"
Write-Host "`n✅ NGINX ready at $ip" -ForegroundColor Cyan
