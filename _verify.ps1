$ErrorActionPreference = "Continue"
$dir = "E:\celechron-windows\build\windows\x64\runner\Release"
$exe = Join-Path $dir "Celechron.exe"
$out = @()

Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600

$before = (Get-Date)

# Create through WMI so the process is NOT a child of this shell.
$res = ([wmiclass]"Win32_Process").Create('"' + $exe + '"', $dir)
$out += "WMI_RETURN=" + $res.ReturnValue + "  PID=" + $res.ProcessId
$target = [int]$res.ProcessId

$alive = $false
for ($i = 1; $i -le 60; $i++) {
  Start-Sleep -Seconds 1
  $p = Get-Process -Id $target -ErrorAction SilentlyContinue
  if (-not $p) {
    $out += "EXITED_AFTER=${i}s"
    break
  }
  if ($i -eq 3 -or $i -eq 10 -or $i -eq 25 -or $i -eq 45 -or $i -eq 60) {
    $out += "T=${i}s MEM=$([math]::Round($p.WorkingSet64/1MB,1))MB HWND=$($p.MainWindowHandle) RESP=$($p.Responding) THREADS=$($p.Threads.Count)"
  }
  if ($i -eq 60) { $alive = $true }
}
$out += "SURVIVED_60s=$alive"

# ---- screenshot the app window only ----
$cs = @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class WinApi {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
try {
  Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction Stop
  $out += "ADD_TYPE=OK"
} catch {
  $out += "ADD_TYPE=FAIL " + $_.Exception.Message
}

if ($alive) {
  $p = Get-Process -Id $target -ErrorAction SilentlyContinue
  if ($p -and $p.MainWindowHandle -ne 0) {
    $h = $p.MainWindowHandle
    [void][WinApi]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 1200
    $r = New-Object RECT
    [void][WinApi]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left
    $hh = $r.Bottom - $r.Top
    $out += "WINDOW=${w}x${hh}"
    try {
      Add-Type -AssemblyName System.Drawing -ErrorAction Stop
      $bmp = New-Object System.Drawing.Bitmap($w, $hh)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $hdc = $g.GetHdc()
      [void][WinApi]::PrintWindow($h, $hdc, 2)
      $g.ReleaseHdc($hdc); $g.Dispose()
      $bmp.Save("E:\celechron-windows\_shot.png", [System.Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
      $out += "SHOT_SAVED=" + (Get-Item "E:\celechron-windows\_shot.png").Length
    } catch {
      $out += "SHOT_FAIL " + $_.Exception.Message
    }
  } else {
    $out += "NO_HWND"
  }
}

# ---- what files did the app touch? proves storage init worked ----
$out += "--- app data written since launch ---"
$bases = @("$env:APPDATA", "$env:LOCALAPPDATA", "$env:USERPROFILE\Documents")
foreach ($b in $bases) {
  $f = Get-ChildItem $b -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
       Where-Object { $_.LastWriteTime -gt $before -and $_.FullName -match 'celechron' } |
       Select-Object -First 6
  foreach ($x in $f) { $out += $x.FullName }
}

Set-Content "E:\celechron-windows\_run_check.txt" -Value $out -Encoding UTF8
