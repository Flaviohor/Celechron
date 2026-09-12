$ErrorActionPreference = "Stop"
$sig = @"
using System;
using System.Runtime.InteropServices;
public class WinApi {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
Add-Type -TypeDefinition $sig -Language CSharp

$p = Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Set-Content "E:\celechron-windows\_cap.txt" -Value "NO_WINDOW" -Encoding UTF8; exit }

$h = $p.MainWindowHandle
[void][WinApi]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 900

$r = New-Object WinApi+RECT
[void][WinApi]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hgt = $r.Bottom - $r.Top

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($w, $hgt)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][WinApi]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save("E:\celechron-windows\_shot.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$lines = @()
$lines += "SIZE=${w}x${hgt}"
$lines += "PID=$($p.Id)"
$lines += "MEM_MB=$([math]::Round($p.WorkingSet64 / 1MB, 1))"
$lines += "THREADS=$($p.Threads.Count)"
$lines += "UPTIME_S=$([math]::Round(((Get-Date) - $p.StartTime).TotalSeconds, 1))"
$lines += "VISIBLE=$([WinApi]::IsWindowVisible($h))"
Set-Content "E:\celechron-windows\_cap.txt" -Value $lines -Encoding UTF8
