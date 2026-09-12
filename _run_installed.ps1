$ErrorActionPreference = "Continue"
$out = @()
$dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Celechron'
$exe = Join-Path $dir 'Celechron.exe'

Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$out += "EXE=" + $exe
$out += "EXISTS=" + (Test-Path $exe)

$res = ([wmiclass]"Win32_Process").Create('"' + $exe + '"', $dir)
$out += "WMI_RETURN=" + $res.ReturnValue + " PID=" + $res.ProcessId
$target = [int]$res.ProcessId

$alive = $false
for ($i = 1; $i -le 20; $i++) {
  Start-Sleep -Seconds 1
  $p = Get-Process -Id $target -ErrorAction SilentlyContinue
  if (-not $p) { $out += "EXITED_AFTER_" + $i + "s"; break }
  if ($i -eq 3 -or $i -eq 12 -or $i -eq 20) {
    $out += "T=" + $i + "s MEM=" + [math]::Round($p.WorkingSet64/1MB,1) + "MB HWND=" + $p.MainWindowHandle + " RESP=" + $p.Responding + " PATH=" + $p.Path
  }
  if ($i -eq 20) { $alive = $true }
}
$out += "INSTALLED_APP_RUNS=" + $alive
Set-Content "E:\celechron-windows\_run_installed.txt" -Value $out -Encoding ASCII
