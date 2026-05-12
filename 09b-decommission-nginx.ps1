# =============================================================================
# 09-cutover-and-decommission.ps1  —  Per-host cutover + remove NGINX
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║                  CUTOVER PLAYBOOK (run per hostname)                 ║
╠══════════════════════════════════════════════════════════════════════╣
║ 1. Confirm Gateway serves the host: ./08-validate-gateway.ps1        ║
║ 2. Production: change DNS A/CNAME -> Gateway IP/FQDN.                ║
║    POC: edit C:\Windows\System32\drivers\etc\hosts:                  ║
║        <gateway-ip>  app1.contoso.local                              ║
║ 3. Wait TTL (production: 24-48h bake per host).                      ║
║ 4. Smoke test from a real client.                                    ║
║ 5. ROLLBACK = revert DNS / hosts entry.                              ║
║ 6. Once all hosts confirmed: delete the matching NGINX Ingress.      ║
║ 7. Once NO Ingress objects remain: helm uninstall ingress-nginx.     ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$ans = Read-Host "Proceed to delete NGINX Ingress objects + uninstall ingress-nginx? (yes/no)"
if ($ans -ne 'yes') { Write-Host "Aborted."; return }

foreach ($ns in @($NS_APP1, $NS_APP2, $NS_APP3)) {
    kubectl -n $ns delete ingress poc-ingress --ignore-not-found
}
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx --ignore-not-found

Write-Host "`n✅ NGINX decommissioned. Gateway API is the sole entry point." -ForegroundColor Green
