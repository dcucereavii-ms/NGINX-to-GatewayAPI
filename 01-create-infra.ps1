# =============================================================================
# 01-create-infra.ps1
#   Reuses existing AKS (rg-gateway-test/aks-gateway-test).
#   Cluster prereqs (OIDC, WI, KV-CSI addon) already enabled — just verifies.
#   Creates a Key Vault and assigns RBAC.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

Write-Host "`n==> Verifying cluster (single call)" -ForegroundColor Green
$info = az aks show -g $RG -n $AKS `
    --query "{power:powerState.code,oidc:oidcIssuerProfile.enabled,wi:securityProfile.workloadIdentity.enabled,kvcsi:addonProfiles.azureKeyvaultSecretsProvider.enabled}" `
    -o json | ConvertFrom-Json
Write-Host ("    Power={0}  OIDC={1}  WI={2}  KV-CSI={3}" -f $info.power,$info.oidc,$info.wi,$info.kvcsi)
if ($info.power -ne "Running") { throw "AKS is not Running. Run: az aks start -g $RG -n $AKS" }
if (-not $info.oidc -or -not $info.wi -or -not $info.kvcsi) {
    throw "Cluster missing required features (OIDC=$($info.oidc) WI=$($info.wi) KV-CSI=$($info.kvcsi))."
}

Write-Host "`n==> Fetching kubeconfig" -ForegroundColor Green
az aks get-credentials -g $RG -n $AKS --overwrite-existing | Out-Null
kubectl get nodes

Write-Host "`n==> Creating Key Vault $KV (RBAC)" -ForegroundColor Green
$existing = az keyvault list -g $RG --query "[?name=='$KV'].name" -o tsv
if (-not $existing) {
    az keyvault create -g $RG -n $KV -l $LOCATION --enable-rbac-authorization true | Out-Null
} else {
    Write-Host "    Key Vault already exists, reusing." -ForegroundColor DarkGray
}
$kvId = az keyvault show -g $RG -n $KV --query id -o tsv
Write-Host "    KV id: $kvId"

Write-Host "`n==> Granting current user 'Key Vault Certificates Officer'" -ForegroundColor Green
$me = az ad signed-in-user show --query id -o tsv
az role assignment create `
    --assignee-object-id $me --assignee-principal-type User `
    --role "Key Vault Certificates Officer" --scope $kvId 2>$null | Out-Null

Write-Host "`n==> Granting AKS KV-CSI addon identity read access on the vault" -ForegroundColor Green
$addonClientId = az aks show -g $RG -n $AKS `
    --query "addonProfiles.azureKeyvaultSecretsProvider.identity.clientId" -o tsv
$addonObjectId = az ad sp show --id $addonClientId --query id -o tsv
foreach ($role in @("Key Vault Secrets User", "Key Vault Certificate User")) {
    az role assignment create `
        --assignee-object-id $addonObjectId --assignee-principal-type ServicePrincipal `
        --role $role --scope $kvId 2>$null | Out-Null
}

$tenant = az account show --query tenantId -o tsv
@(
    "KV=$KV",
    "TENANT_ID=$tenant",
    "KV_CLIENT_ID=$addonClientId"
) | Set-Content "$PSScriptRoot/.poc-state"

Write-Host "`nReady. KV=$KV  Tenant=$tenant  KvAddonClientId=$addonClientId" -ForegroundColor Cyan
