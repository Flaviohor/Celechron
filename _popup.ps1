$ErrorActionPreference = "Continue"
$out = @()
$out += "--- powershell processes with a visible window ---"
Get-Process -Name powershell, powershell_ise, WScript, cscript -ErrorAction SilentlyContinue | ForEach-Object {
  $out += ("PID=" + $_.Id + " TITLE=[" + $_.MainWindowTitle + "] HWND=" + $_.MainWindowHandle)
}
$out += "--- env check ---"
$out += "APPDATA(from env)=" + $env:APPDATA
$out += "APPDATA(GetFolderPath)=" + [Environment]::GetFolderPath('ApplicationData')
$out += "Programs(GetFolderPath)=" + [Environment]::GetFolderPath('Programs')
$out += "Desktop(GetFolderPath)=" + [Environment]::GetFolderPath('Desktop')
$out += "LocalAppData(GetFolderPath)=" + [Environment]::GetFolderPath('LocalApplicationData')
$out += "--- Celechron process ---"
$c = Get-Process -Name Celechron -ErrorAction SilentlyContinue
if ($c) { $out += "RUNNING PID=" + $c.Id } else { $out += "not running" }
Set-Content "E:\celechron-windows\_popup.txt" -Value $out -Encoding UTF8
