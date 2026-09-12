$ErrorActionPreference = "Continue"
$out = @()

$cs = @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class Cap {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDpiForWindow(IntPtr h);
}
'@
Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction SilentlyContinue

# make THIS process DPI aware so GetWindowRect returns real physical pixels
[void][Cap]::SetProcessDPIAware()

$p = Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Set-Content "E:\celechron-windows\_cap2.txt" -Value "NOT_RUNNING" -Encoding UTF8; exit }

$h = $p.MainWindowHandle
$out += "PID=" + $p.Id + " UPTIME=$([math]::Round(((Get-Date)-$p.StartTime).TotalSeconds))s MEM=$([math]::Round($p.WorkingSet64/1MB,1))MB"

$dpi = [Cap]::GetDpiForWindow($h)
$scale = [math]::Round($dpi / 96.0, 2)
$out += "DPI=$dpi  SCALE=$scale"

[void][Cap]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 1500

$r = New-Object RECT
[void][Cap]::GetWindowRect($h, [ref]$r)
$c = New-Object RECT
[void][Cap]::GetClientRect($h, [ref]$c)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$out += "WINDOW_PHYS=${w}x${hh}"
$out += "CLIENT_PHYS=$($c.Right)x$($c.Bottom)"
$out += "CLIENT_LOGICAL=$([math]::Round($c.Right/$scale))x$([math]::Round($c.Bottom/$scale))"

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Cap]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save("E:\celechron-windows\_shot2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$out += "PRINTWINDOW_OK=$ok"
$bmp.Dispose()

Set-Content "E:\celechron-windows\_cap2.txt" -Value $out -Encoding UTF8
