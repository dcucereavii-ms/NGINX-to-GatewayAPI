# =============================================================================
# 06b-install-ngf.ps1  —  NGINX Gateway Fabric
#   Docs: https://docs.nginx.com/nginx-gateway-fabric/
#
# WARNING: This script is an ALTERNATIVE path. Do NOT run it on a cluster that
# already has the AKS managed Gateway API add-on enabled (the primary path of
# this POC, set up in 01-create-infra.ps1). On such clusters the AKS admission
# webhook owns the Gateway API CRDs and will reject the apply below.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

Write-Host "==> Installing Gateway API CRDs (standard channel)" -ForegroundColor Green
# CRDs are too large for client-side apply since v1.3+ — use server-side apply.
# Skip this on clusters with managed Gateway API enabled (CRDs are managed by AKS).
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml | Out-Null

Write-Host "==> Helm installing NGINX Gateway Fabric" -ForegroundColor Green
helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric `
    --namespace nginx-gateway --create-namespace `
    --set service.type=LoadBalancer | Out-Null

Write-Host "==> Waiting for NGF LoadBalancer IP..." -ForegroundColor Green
$ip = $null
for ($i = 0; $i -lt 60; $i++) {
    $ip = kubectl get svc ngf-nginx-gateway-fabric -n nginx-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ip) { break }
    Start-Sleep -Seconds 5
}
if (-not $ip) { throw "NGF LoadBalancer IP not assigned." }

"NGF_IP=$ip" | Add-Content "$PSScriptRoot/.poc-state"
Write-Host "`n✅ NGF ready at $ip" -ForegroundColor Cyan
