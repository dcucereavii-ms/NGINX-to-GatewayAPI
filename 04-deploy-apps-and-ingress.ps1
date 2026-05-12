# =============================================================================
# 04-deploy-apps-and-ingress.ps1
#   - 3 demo apps (echo) in 3 namespaces
#   - SecretProviderClass per app to pull cert from Key Vault and SYNC as tls Secret
#   - "syncer" pause pod to keep the SPC volume mounted (required for sync)
#   - Multi-host / multi-cert NGINX Ingress
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

# Load TENANT_ID and KV_CLIENT_ID from state
Get-Content "$PSScriptRoot/.poc-state" | ForEach-Object {
    $k,$v = $_.Split('=',2); Set-Variable -Name $k -Value $v -Scope Global
}

$manifestDir = Join-Path $PSScriptRoot "manifests"
$apps = @(
    @{ Ns=$NS_APP1; App="app1"; Host=$HOST_APP1; Cert=$CERT_APP1 },
    @{ Ns=$NS_APP2; App="app2"; Host=$HOST_APP2; Cert=$CERT_APP2 },
    @{ Ns=$NS_APP3; App="app3"; Host=$HOST_APP3; Cert=$CERT_DEV  }
)

foreach ($a in $apps) {
    Write-Host "`n==> Deploying $($a.App) in namespace $($a.Ns)" -ForegroundColor Green
    kubectl create namespace $a.Ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null

    # Render & apply app + SPC + syncer
    $tpl = Get-Content "$manifestDir/apps/app-template.yaml" -Raw
    $rendered = $tpl `
        -replace '__NS__',          $a.Ns `
        -replace '__APP__',         $a.App `
        -replace '__HOST__',        $a.Host `
        -replace '__CERT_NAME__',   $a.Cert `
        -replace '__KV_NAME__',     $KV `
        -replace '__TENANT_ID__',   $TENANT_ID `
        -replace '__KV_CLIENT_ID__',$KV_CLIENT_ID
    $rendered | kubectl apply -f - | Out-Null
}

Write-Host "`n==> Waiting for tls Secrets to materialize (CSI driver sync)..." -ForegroundColor Green
foreach ($a in $apps) {
    for ($i=0; $i -lt 30; $i++) {
        $exists = kubectl -n $a.Ns get secret "tls-$($a.App)" --ignore-not-found -o name 2>$null
        if ($exists) { Write-Host "   ✓ tls-$($a.App) ready"; break }
        Start-Sleep -Seconds 4
    }
}

Write-Host "`n==> Applying multi-host / multi-cert Ingress" -ForegroundColor Green
$ing = Get-Content "$manifestDir/nginx/ingress.yaml" -Raw
$ing = $ing `
    -replace '__HOST_APP1__', $HOST_APP1 `
    -replace '__HOST_APP2__', $HOST_APP2 `
    -replace '__HOST_APP3__', $HOST_APP3
$ing | kubectl apply -f - | Out-Null

Write-Host "`n✅ Apps + Ingress deployed" -ForegroundColor Cyan
kubectl get ingress -A
