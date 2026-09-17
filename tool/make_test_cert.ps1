# Generate a self-signed code-signing certificate for local dev / internal
# distribution.
#
# WHAT THIS GIVES YOU:
#   - Files you sign show "SelfService Code Signing (TEST ONLY)" in the
#     publisher field (right-click .exe -> Properties -> Digital Signatures).
#   - You can run signtool.exe / verify on the local machine if you also
#     allow the script to import the cert into Cert:\LocalMachine\Root
#     (requires admin).
#   - Internal Windows GPO policies that require a signed binary are satisfied.
#
# WHAT THIS DOES NOT GIVE YOU:
#   - SmartScreen reputation. Microsoft treats self-signed binaries the same
#     as unsigned binaries -- users will still see the "Windows protected
#     your PC" prompt. There is no way around this without a paid certificate.
#
# The certificate is placed in Cert:\CurrentUser\My (your personal store).
# Its private key is NOT exportable and is bound to your Windows account --
# logging out of the account deletes the key.
#
# Usage:
#   powershell tool/make_test_cert.ps1
#   powershell tool/make_test_cert.ps1 -Subject 'CN=My Team Internal' -ValidYears 3
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

[CmdletBinding()]
param(
    [string]$Subject = 'CN=PCelechron Dev Signing (TEST ONLY, not for distribution)',
    [int]$ValidYears = 5,
    [string]$FriendlyName = 'PCelechron Test Code Signing'
)

$ErrorActionPreference = 'Stop'

if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
    throw "Windows only."
}

# Already have one?
$existing = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq $Subject -and $_.HasPrivateKey }
if ($existing) {
    Write-Host "Certificate already exists. Skipping generation." -ForegroundColor Yellow
    $existing | Format-List Subject, Thumbprint, NotBefore, NotAfter
    exit 0
}

Write-Host "Generating self-signed code-signing certificate..."
Write-Host ("  Subject      : " + $Subject)
Write-Host ("  Valid for    : " + $ValidYears + " years")
Write-Host ("  FriendlyName : " + $FriendlyName)

$cert = New-SelfSignedCertificate `
    -Subject $Subject `
    -Type CodeSigningCert `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears($ValidYears) `
    -FriendlyName $FriendlyName

# Optional: also place in LocalMachine\Root so signtool verify /pa works.
# Needs admin. Skip silently if we don't have it.
$alreadyRoot = Get-ChildItem -Path 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue |
               Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
if (-not $alreadyRoot) {
    try {
        $tempPfx = Join-Path $env:TEMP "pcelechron-test-cert-$($cert.Thumbprint).cer"
        Export-Certificate -Cert $cert -FilePath $tempPfx -Type CERT | Out-Null
        Import-Certificate -FilePath $tempPfx `
                           -CertStoreLocation 'Cert:\LocalMachine\Root' `
                           -ErrorAction Stop | Out-Null
        Remove-Item $tempPfx -Force -ErrorAction SilentlyContinue
        Write-Host "  Also imported into LocalMachine\Root (admin was available) -- signtool verify /pa will now pass locally." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not import into LocalMachine\Root (probably no admin). signtool verify /pa will still fail, but the signature is present."
    }
}

Write-Host ""
Write-Host "==== Certificate generated ====" -ForegroundColor Green
$cert | Format-List Subject, Thumbprint, NotBefore, NotAfter, HasPrivateKey
Write-Host ""
Write-Host "Thumbprint: $($cert.Thumbprint)"
Write-Host "Sign with: powershell tool/sign.ps1 -Path <file>   (the script will auto-pick this cert)"