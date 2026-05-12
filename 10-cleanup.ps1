# =============================================================================
# 10-cleanup.ps1  —  Delete the entire resource group. IRREVERSIBLE.
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"

$ans = Read-Host "Delete resource group $RG and ALL resources in it? Type the RG name to confirm"
if ($ans -ne $RG) { Write-Host "Aborted."; return }

az group delete -n $RG --yes --no-wait
Write-Host "✅ Deletion started in background." -ForegroundColor Green
