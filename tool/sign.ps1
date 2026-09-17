# Authenticode signature helper for PCelechron dist artifacts.
#
# Wraps the Windows SDK `signtool.exe`. Without a real OV/EV certificate,
# SmartScreen will still warn the user -- this script does not magically
# fix that. What it does:
#   - attach an Authenticode signature to .exe / .dll
#   - include an RFC3161 timestamp so the signature stays valid past the
#     certificate's NotAfter
#   - print SignerCertificate.Subject after signing so the operator can
#     visually confirm which identity was used
#
# Usage:
#   powershell tool/sign.ps1 -Path dist\PCelechron-1.0.2-windows-x64\PCelechron.exe
#   powershell tool/sign.ps1 -Path dist\PCelechron-*-setup.exe -Subject 'CN=PCelechron contributors'
#   powershell tool/sign.ps1 -Path dist\PCelechron-1.0.2-windows-x64 -Recurse
#   powershell tool/sign.ps1 -Path foo.exe -VerifyOnly
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7 (pwsh.exe).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string[]]$Path,
    [switch]$Recurse,
    [string]$Thumbprint,
    [string]$Subject,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [string]$Description,
    [string]$Url,
    [switch]$VerifyOnly,
    [switch]$NoTimestamp
)

$ErrorActionPreference = 'Stop'

# ---- locate signtool.exe ---------------------------------------------------
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signtool = Get-ChildItem -Path (Join-Path $sdkRoot '*\x64\signtool.exe') `
                         -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
if (-not $signtool) {
    throw "signtool.exe not found. Install Windows SDK.`n" +
          "Looked in: $sdkRoot"
}
Write-Host "signtool: $signtool" -ForegroundColor DarkGray

# ---- expand input files ---------------------------------------------------
$expanded = New-Object System.Collections.Generic.List[string]
foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Warning "Not found, skipped: $p"; continue }
    if ((Get-Item -LiteralPath $p).PSIsContainer) {
        $pat = if ($Recurse) { Get-ChildItem -Path $p -Recurse -File -Include *.exe, *.dll }
               else { Get-ChildItem -Path $p -File -Include *.exe, *.dll }
        foreach ($f in $pat) { $expanded.Add($f.FullName) }
    } else {
        $expanded.Add($p)
    }
}
if ($expanded.Count -eq 0) { throw "No .exe / .dll files to process." }

# ---- verify-only path -----------------------------------------------------
if ($VerifyOnly) {
    foreach ($p in $expanded) {
        Write-Host "Verify: $p" -ForegroundColor Cyan
        & $signtool verify /pa $p
        if ($LASTEXITCODE -ne 0) { Write-Warning "  -> verify returned $LASTEXITCODE (self-signed certs will fail this -- normal)" }
    }
    return
}

# ---- build signtool arguments --------------------------------------------
$args = @('sign', '/fd', 'SHA256')
if ($Thumbprint) { $args += @('/sha1', $Thumbprint) }
elseif ($Subject) { $args += @('/n', $Subject) }
else { $args += '/a' }
if (-not $NoTimestamp) { $args += @('/tr', $TimestampServer, '/td', 'SHA256') }
if ($Description) { $args += @('/d', $Description) }
if ($Url) { $args += @('/du', $Url) }

# ---- main loop ------------------------------------------------------------
foreach ($p in $expanded) {
    $abs = (Resolve-Path -LiteralPath $p).Path
    Write-Host "Sign: $abs" -ForegroundColor Cyan
    & $signtool @args $abs
    if ($LASTEXITCODE -ne 0) { throw "signtool failed (exit=$LASTEXITCODE) for $abs" }

    $sig = Get-AuthenticodeSignature -LiteralPath $abs
    Write-Host ("  -> Status      : " + $sig.Status)
    Write-Host ("  -> Signer CN   : " + ($sig.SignerCertificate.Subject -join ','))
    Write-Host ("  -> NotAfter    : " + $sig.SignerCertificate.NotAfter)
    if ($sig.TimeStamperCertificate) {
        Write-Host ("  -> Timestamp   : " + ($sig.TimeStamperCertificate.Subject -join ',') + ' @ ' + $sig.TimeStamperCertificate.NotAfter)
    } else {
        Write-Host "  -> Timestamp   : (none -- signatures will expire with the cert)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "After signing, right-click the .exe -> Properties -> Digital Signatures to see the publisher name." -ForegroundColor Green
Write-Host "If the certificate is self-signed, SmartScreen still warns -- see WINDOWS_PORT.md for what does and doesn't help."