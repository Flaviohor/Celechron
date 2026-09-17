# Sign every PE file under dist/ in the correct order.
#
# PCelechron dist layout:
#   dist/PCelechron-<ver>-windows-x64/PCelechron.exe
#   dist/PCelechron-<ver>-windows-x64/flutter_windows.dll
#   dist/PCelechron-<ver>-windows-x64/*_plugin.dll
#   dist/PCelechron-<ver>-windows-x64-setup.exe
#
# Signing order matters: signtool Authenticode signatures only cover a PE's
# own bytes. If we signed the IExpress wrapper (Setup.exe) first, then signed
# the inner files, the wrapper's hash would no longer match its signature.
# So:
#   1. Sign everything inside the portable directory first
#   2. Sign Setup.exe last
#
# If no code-signing certificate is available in Cert:\CurrentUser\My this
# script does NOT fail the build -- it prints a yellow warning and exits 0.
# That is on purpose: the build pipeline should still produce usable artifacts
# even without a cert.
#
# Usage:
#   powershell tool/sign_dist.ps1
#   powershell tool/sign_dist.ps1 -DistDir .\dist -Subject 'CN=PCelechron contributors'
#   powershell tool/sign_dist.ps1 -SkipInstaller
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

[CmdletBinding()]
param(
    [string]$DistDir = 'dist',
    [string]$Subject,
    [string]$Thumbprint,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$signScript = Join-Path $here 'sign.ps1'

# Pick a PowerShell host: pwsh first, fall back to powershell.
$psExe = (Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue).Source
if (-not $psExe) { $psExe = (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue).Source }
if (-not $psExe) { throw "No PowerShell host found." }

if (-not (Test-Path -LiteralPath $DistDir)) { throw "Dist directory not found: $DistDir" }
$distAbs = (Resolve-Path -LiteralPath $DistDir).Path
Write-Host "Dist: $distAbs" -ForegroundColor DarkGray

# ---- find a usable code-signing certificate --------------------------------
# OID 1.3.6.1.5.5.7.3.3 = Code Signing. FriendlyName is localised on
# Chinese Windows ("代码签名") so checking the OID value is safest.
$codeSigningOid = '1.3.6.1.5.5.7.3.3'
$cert = $null
$certs = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
          Where-Object {
              $_.HasPrivateKey -and
              ($_.Extensions | Where-Object {
                  ($_.Oid.Value -eq $codeSigningOid) -or
                  ($_.Oid.FriendlyName -match 'Code Signing|\u4ee3\u7801\u7b7e\u540d')
              }) -and
              (-not $Subject -or $_.Subject -like "*$Subject*") -and
              (-not $Thumbprint -or $_.Thumbprint -eq $Thumbprint)
          }
if ($certs) { $cert = $certs | Select-Object -First 1 }

if (-not $cert) {
    Write-Warning "No usable code-signing certificate in Cert:\CurrentUser\My." -ForegroundColor Yellow
    Write-Warning "  Open certmgr.msc -> Personal -> Certificates." -ForegroundColor Yellow
    Write-Warning "  Need a cert with 'Code Signing' EKU AND a private key." -ForegroundColor Yellow
    Write-Warning "  Generate a self-signed one: powershell tool/make_test_cert.ps1" -ForegroundColor Yellow
    Write-Warning "  See WINDOWS_PORT.md for what this gets you (and doesn't)." -ForegroundColor Yellow
    exit 0
}
Write-Host "Using certificate:" -ForegroundColor DarkGray
Write-Host ("  Subject    : " + $cert.Subject)
Write-Host ("  Thumbprint : " + $cert.Thumbprint)
Write-Host ("  NotAfter   : " + $cert.NotAfter)

# ---- locate artifacts ----------------------------------------------------
$portable = Get-ChildItem -Path $distAbs -Directory |
            Where-Object { $_.Name -like 'PCelechron-*-windows-x64' } |
            Select-Object -First 1
$installer = Get-ChildItem -Path $distAbs -File |
             Where-Object { $_.Name -like 'PCelechron-*-windows-x64-setup.exe' } |
             Select-Object -First 1

if (-not $portable -and -not $installer) {
    throw "No PCelechron artifacts found in $distAbs. Run tool/build.sh then tool/package.py first."
}

# ---- sign the portable directory's PE files ---------------------------
if ($portable) {
    Write-Host "`n[1/2] Sign portable directory" -ForegroundColor Green
    $signArgs = @{
        Path        = $portable.FullName
        Recurse     = $true
        Subject     = $cert.Subject
        Description = 'PCelechron - course schedule and study helper'
        Url         = 'https://github.com/Celechron/Celechron'
    }
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $signScript @signArgs
    if ($LASTEXITCODE -ne 0) { throw "Signing the portable directory failed." }
}

# ---- sign the installer last ------------------------------------------
if ($installer -and -not $SkipInstaller) {
    Write-Host "`n[2/2] Sign installer" -ForegroundColor Green
    $signArgs = @{
        Path        = $installer.FullName
        Subject     = $cert.Subject
        Description = 'PCelechron setup'
        Url         = 'https://github.com/Celechron/Celechron'
    }
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $signScript @signArgs
    if ($LASTEXITCODE -ne 0) { throw "Signing the installer failed." }
}

Write-Host "`n==== Done ====" -ForegroundColor Green
Write-Host ("Portable : " + $portable.FullName)
Write-Host ("Installer: " + $installer.FullName)
Write-Host "`nReminder: self-signed certificates do NOT earn SmartScreen trust." -ForegroundColor Yellow
Write-Host "          Real certificates cost money; see WINDOWS_PORT.md for the free alternatives." -ForegroundColor Yellow