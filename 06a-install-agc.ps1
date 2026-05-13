# =============================================================================
# 06a-install-agc.ps1  —  Azure Application Gateway for Containers
#   Docs: https://learn.microsoft.com/azure/application-gateway/for-containers/
#
# WARNING: This script is an ALTERNATIVE path. Do NOT run it on a cluster that
# already has the AKS managed Gateway API add-on enabled (the primary path of
# this POC, set up in 01-create-infra.ps1). On such clusters the AKS admission
# webhook owns the Gateway API CRDs and will reject the apply below.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

Write-Host "==> Registering required providers/features (idempotent)" -ForegroundColor Green
az provider register --namespace Microsoft.ContainerService | Out-Null
az provider register --namespace Microsoft.ServiceNetworking | Out-Null

Write-Host "==> Installing Gateway API CRDs (standard channel)" -ForegroundColor Green
# CRDs are too large for client-side apply since v1.3+ — use server-side apply.
# Skip this on clusters with managed Gateway API enabled (CRDs are managed by AKS).
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml | Out-Null

Write-Host "==> Creating user-assigned identity for ALB controller" -ForegroundColor Green
$IDENTITY = "$PREFIX-alb-id"
az identity create -g $RG -n $IDENTITY -l $LOCATION | Out-Null
$identityClientId = az identity show -g $RG -n $IDENTITY --query clientId -o tsv
$identityPrincipalId = az identity show -g $RG -n $IDENTITY --query principalId -o tsv
$mcRg = az aks show -g $RG -n $AKS --query nodeResourceGroup -o tsv

# AppGw for Containers Configuration Manager role on the AKS node RG
az role assignment create --assignee-object-id $identityPrincipalId --assignee-principal-type ServicePrincipal `
    --role "fbc52c3f-28ad-4303-a892-8a056630b8f1" `
    --scope (az group show -n $mcRg --query id -o tsv) | Out-Null
# Reader on RG for the controller
az role assignment create --assignee-object-id $identityPrincipalId --assignee-principal-type ServicePrincipal `
    --role "Reader" `
    --scope (az group show -n $RG --query id -o tsv) | Out-Null

Write-Host "==> Federating identity for the controller SA" -ForegroundColor Green
$oidc = az aks show -g $RG -n $AKS --query oidcIssuerProfile.issuerUrl -o tsv
az identity federated-credential create -g $RG -n alb-fc --identity-name $IDENTITY `
    --issuer $oidc --subject "system:serviceaccount:azure-alb-system:alb-controller-sa" `
    --audience api://AzureADTokenExchange | Out-Null

Write-Host "==> Helm installing alb-controller" -ForegroundColor Green
# Check the latest chart version before running:
#   helm show chart oci://mcr.microsoft.com/application-lb/charts/alb-controller
# Pin to a specific version in production; omit --version to track latest.
helm upgrade --install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller `
    --namespace azure-alb-system --create-namespace `
    --set albController.namespace=azure-alb-system `
    --set albController.podIdentity.clientID=$identityClientId | Out-Null

Write-Host "`n✅ AGC controller installed. The ALB resource is created on first Gateway apply." -ForegroundColor Cyan
"AGC_IDENTITY_CLIENT_ID=$identityClientId" | Add-Content "$PSScriptRoot/.poc-state"
