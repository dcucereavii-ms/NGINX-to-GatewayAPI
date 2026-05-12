# =============================================================================
# 02-generate-certs.ps1  —  Self-signed PFXs via PowerShell, imported to KV
# =============================================================================
. "$PSScriptRoot/00-variables.ps1"
$ErrorActionPreference = "Stop"

$work = Join-Path $PSScriptRoot ".certs"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$pfxPwd = ConvertTo-SecureString -String "PocPass!" -Force -AsPlainText

function New-SelfSignedPfx {
    param([string]$CommonName, [string]$PfxPath)
    Write-Host "  - Generating cert for CN=$CommonName" -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -DnsName $CommonName `
        -Subject "CN=$CommonName" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(1) `
        -KeyUsage DigitalSignature,KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")
    Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $pfxPwd | Out-Null
    Remove-Item ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -Force
    if (-not (Test-Path $PfxPath)) { throw "Failed to create $PfxPath" }
}

$certMap = @(
    @{ Cn = $HOST_APP1;     Name = $CERT_APP1 },
    @{ Cn = $HOST_APP2;     Name = $CERT_APP2 },
    @{ Cn = $HOST_WILDCARD; Name = $CERT_DEV  }
)

foreach ($c in $certMap) {
    $pfx = Join-Path $work "$($c.Name).pfx"
    New-SelfSignedPfx -CommonName $c.Cn -PfxPath $pfx
    Write-Host "==> Importing $($c.Name) into $KV" -ForegroundColor Green
    az keyvault certificate import `
        --vault-name $KV `
        --name $c.Name `
        --file $pfx `
        --password "PocPass!" | Out-Null
}

Write-Host "`n3 certs imported into $KV :" -ForegroundColor Cyan
az keyvault certificate list --vault-name $KV --query "[].name" -o tsv
