# 07-deploy-gateway-and-routes.ps1 — managed Gateway API via App Routing + Istio
. $PSScriptRoot/00-variables.ps1
Initialize-Poc

Write-Host "==> Ensuring namespace $($global:NS_GW)" -ForegroundColor Cyan
kubectl create namespace $global:NS_GW --dry-run=client -o yaml | kubectl apply -f -

$tpl = Get-Content "$PSScriptRoot/manifests/istio/gateway.yaml" -Raw
$rendered = $tpl `
    -replace '__GW__',           $global:GW_NAME `
    -replace '__NS_GW__',        $global:NS_GW `
    -replace '__NS_APP1__',      $global:NS_APP1 `
    -replace '__NS_APP2__',      $global:NS_APP2 `
    -replace '__NS_APP3__',      $global:NS_APP3 `
    -replace '__HOST_APP1__',    $global:HOST_APP1 `
    -replace '__HOST_APP2__',    $global:HOST_APP2 `
    -replace '__HOST_APP3__',    $global:HOST_APP3 `
    -replace '__HOST_WILDCARD__', $global:HOST_WILDCARD

$tmp = New-TemporaryFile
$rendered | Set-Content $tmp.FullName -Encoding utf8
Write-Host "==> Applying Gateway + HTTPRoutes + ReferenceGrants" -ForegroundColor Cyan
kubectl apply -f $tmp.FullName
Remove-Item $tmp.FullName -Force

Write-Host ""
Write-Host "==> Waiting for Gateway to be Programmed..." -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    $cond = kubectl get gateway $global:GW_NAME -n $global:NS_GW -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>$null
    if ($cond -eq 'True') { $ok = $true; break }
    Start-Sleep 5
}
if (-not $ok) {
    Write-Warning "Gateway not Programmed after 5 min. Current status:"
    kubectl describe gateway $global:GW_NAME -n $global:NS_GW
    exit 1
}
Write-Host "Gateway is Programmed." -ForegroundColor Green

Write-Host ""
Write-Host "==> Discovering Gateway service IP" -ForegroundColor Cyan
# App Routing creates a Service named <gateway-name>-istio in the same namespace
$svc = "$($global:GW_NAME)-istio"
$gwIp = $null
for ($i = 0; $i -lt 60; $i++) {
    $gwIp = kubectl get svc $svc -n $global:NS_GW -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($gwIp) { break }
    Start-Sleep 5
}
if (-not $gwIp) {
    Write-Warning "Gateway service '$svc' has no LB IP yet. Checking listeners status..."
    kubectl get svc -n $global:NS_GW
    kubectl get gateway $global:GW_NAME -n $global:NS_GW -o yaml | Select-String -Pattern 'address|hostname|ip'
    exit 1
}

Write-Host "Gateway external IP: $gwIp" -ForegroundColor Green

# Persist GW_IP into .poc-state
$state = Get-Content "$PSScriptRoot/.poc-state" -Raw | ConvertFrom-Json
$state | Add-Member -NotePropertyName GW_IP -NotePropertyValue $gwIp -Force
$state | ConvertTo-Json | Set-Content "$PSScriptRoot/.poc-state" -Encoding utf8

Write-Host ""
Write-Host "==> Routes status" -ForegroundColor Cyan
kubectl get httproute -A
