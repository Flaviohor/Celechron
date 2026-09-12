$ErrorActionPreference = "Continue"
$dir = "E:\celechron-windows\dist\Celechron-1.3.0-windows-x64"
$exe = Join-Path $dir "Celechron.exe"
$out = @()

Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600

if (-not (Test-Path $exe)) { Set-Content "E:\celechron-windows\_pkgrun.txt" -Value "EXE_MISSING" -Encoding ASCII; exit }

$res = ([wmiclass]"Win32_Process").Create('"' + $exe + '"', $dir)
$out += "WMI_RETURN=" + $res.ReturnValue + " PID=" + $res.ProcessId
$target = [int]$res.ProcessId

for ($i = 1; $i -le 25; $i++) {
  Start-Sleep -Seconds 1
  $p = Get-Process -Id $target -ErrorAction SilentlyContinue
  if (-not $p) { $out += "EXITED_AFTER_" + $i + "s  -> PORTABLE START FAILED"; break }
  if ($i -eq 3 -or $i -eq 10 -or $i -eq 25) {
    $mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $out += "T=" + $i + "s MEM=" + $mb + "MB HWND=" + $p.MainWindowHandle + " RESP=" + $p.Responding
  }
  if ($i -eq 25) { $out += "PORTABLE_PKG_RUNS=OK" }
}
Set-Content "E:\celechron-windows\_pkgrun.txt" -Value $out -Encoding ASCII
