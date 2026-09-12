$ErrorActionPreference = "Continue"
$dir = "E:\celechron-windows\build\windows\x64\runner\Release"
$exe = Join-Path $dir "Celechron.exe"

Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$log = @()
$log += "START=" + (Get-Date -Format "HH:mm:ss.fff")

$proc = Start-Process -FilePath $exe -WorkingDirectory $dir -PassThru `
  -RedirectStandardOutput "E:\celechron-windows\_stdout.txt" `
  -RedirectStandardError "E:\celechron-windows\_stderr.txt"

$log += "PID=" + $proc.Id

$died = $false
for ($i = 1; $i -le 45; $i++) {
  Start-Sleep -Seconds 1
  $proc.Refresh()
  if ($proc.HasExited) {
    $log += "EXITED_AFTER=${i}s"
    $log += "EXITCODE=" + $proc.ExitCode
    $died = $true
    break
  }
  if ($i -eq 5 -or $i -eq 15 -or $i -eq 30 -or $i -eq 45) {
    $log += "T=${i}s ALIVE MEM=$([math]::Round($proc.WorkingSet64/1MB,1))MB RESP=$($proc.Responding) HWND=$($proc.MainWindowHandle)"
  }
}

if (-not $died) {
  $log += "STILL_ALIVE_AFTER_45s"
}

Set-Content "E:\celechron-windows\_monitor.txt" -Value $log -Encoding UTF8
