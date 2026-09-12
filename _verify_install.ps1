$ErrorActionPreference = "Continue"
$out = @()
$target = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Celechron'

$out += "=== 1. install dir: $target ==="
if (Test-Path $target) {
  $files = Get-ChildItem $target -Recurse -File
  $out += "files=" + $files.Count + "  size=" + [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1) + " MB"
  foreach ($n in @('Celechron.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data\app.so','data\icudtl.dat'))
  {
    $p = Join-Path $target $n
    if (Test-Path $p) { $out += "  OK   $n" } else { $out += "  MISS $n" }
  }
} else { $out += "NOT INSTALLED" }

$out += ""
$out += "=== 2. shortcuts ==="
$sm = Join-Path ([Environment]::GetFolderPath('Programs')) 'Celechron.lnk'
$dk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Celechron.lnk'
foreach ($p in @($sm, $dk)) {
  if (Test-Path $p) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($p)
    $out += "  OK   " + $p + "  -> " + $lnk.TargetPath
  } else { $out += "  MISS " + $p }
}

$out += ""
$out += "=== 3. celechron:// protocol ==="
$proto = 'HKCU:\Software\Classes\celechron'
if (Test-Path $proto) {
  $out += "  HKCU:\Software\Classes\celechron  EXISTS"
  $out += "  (default) = " + (Get-ItemProperty $proto -Name '(default)' -EA SilentlyContinue).'(default)'
  $out += "  URL Protocol = [" + (Get-ItemProperty $proto -Name 'URL Protocol' -EA SilentlyContinue).'URL Protocol' + "]"
  $cmd = Join-Path $proto 'shell\open\command'
  $out += "  command = " + (Get-ItemProperty $cmd -Name '(default)' -EA SilentlyContinue).'(default)'
} else { $out += "  MISSING" }

$out += ""
$out += "=== 4. uninstall entry (Apps & Features) ==="
$un = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Celechron'
if (Test-Path $un) {
  $k = Get-ItemProperty $un
  $out += "  DisplayName    = " + $k.DisplayName
  $out += "  DisplayVersion = " + $k.DisplayVersion
  $out += "  Publisher      = " + $k.Publisher
  $out += "  InstallLocation= " + $k.InstallLocation
  $out += "  UninstallString= " + $k.UninstallString
  $out += "  DisplayIcon    = " + $k.DisplayIcon
} else { $out += "  MISSING" }

$out += ""
$out += "=== 5. running process ==="
$p = Get-Process -Name Celechron -ErrorAction SilentlyContinue
if ($p) {
  $out += "  PID=" + $p.Id + " MEM=" + [math]::Round($p.WorkingSet64/1MB,1) + "MB HWND=" + $p.MainWindowHandle + " RESP=" + $p.Responding
  $out += "  PATH=" + $p.Path
} else { $out += "  NOT RUNNING" }

Set-Content "E:\celechron-windows\_verify_install.txt" -Value $out -Encoding UTF8
