# =============================================================================
# 00-variables.ps1  —  central config for the POC. Dot-source from every step.
# =============================================================================

# ---- Existing resources (reused) ----
$global:SUBSCRIPTION_ID = "e550fb1a-dd92-4ffc-ab4a-363e04ffe7c3"
$global:RG              = "rg-gateway-test"
$global:AKS             = "aks-gateway-test"
$global:LOCATION        = "canadacentral"

# ---- New resources created by the POC ----
$global:PREFIX          = "gwpoc$((Get-Random -Minimum 1000 -Maximum 9999))"
$global:KV              = "$PREFIX-kv"

# ---- Demo hostnames (NOT real DNS — validated via curl --resolve) ----
$global:HOST_APP1     = "app1.contoso.local"
$global:HOST_APP2     = "app2.contoso.local"
$global:HOST_APP3     = "app3.dev.contoso.local"
$global:HOST_WILDCARD = "*.dev.contoso.local"

# ---- Key Vault cert names ----
$global:CERT_APP1 = "cert-app1"
$global:CERT_APP2 = "cert-app2"
$global:CERT_DEV  = "cert-dev-wildcard"

# ---- K8s namespaces ----
$global:NS_APP1 = "app1"
$global:NS_APP2 = "app2"
$global:NS_APP3 = "app3"
$global:NS_GW   = "gw"

# ---- Gateway names ----
$global:GW_NAME = "poc-gateway"

# ---- Gateway LoadBalancer exposure ----
# Set to $true to provision the App Routing Istio Gateway behind an INTERNAL
# Azure Load Balancer (private IP only). Set to $false for a public IP (default).
$global:INTERNAL_LB = $false
# Optional: pin the internal LB to a specific subnet (must exist in the AKS
# vnet). Leave empty to let the cloud-provider pick the node subnet.
$global:INTERNAL_LB_SUBNET = ""

function Initialize-Poc {
    az account set --subscription $SUBSCRIPTION_ID | Out-Null
    $sub = az account show --query name -o tsv
    Write-Host "Subscription: $sub" -ForegroundColor Cyan
    Write-Host "Resource group: $RG  (existing)"
    Write-Host "AKS: $AKS  (existing)  |  Region: $LOCATION"
    Write-Host "Key Vault (new): $KV"
    Write-Host "Hosts: $HOST_APP1 / $HOST_APP2 / $HOST_APP3 (wildcard $HOST_WILDCARD)"
}

Initialize-Poc

# Persist KV name across script invocations so re-running doesn't randomize it
$stateFile = Join-Path $PSScriptRoot ".poc-state"
if (Test-Path $stateFile) {
    $kvFromState = (Get-Content $stateFile | Where-Object { $_ -like "KV=*" }) -replace '^KV=',''
    if ($kvFromState) { $global:KV = $kvFromState; Write-Host "Reusing KV from state: $KV" -ForegroundColor DarkGray }
}
