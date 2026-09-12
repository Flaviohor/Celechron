$ErrorActionPreference = "Continue"
$out = @()

$cs = @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction SilentlyContinue
[void][W]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$p = Get-Process -Name "Celechron" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Set-Content "E:\celechron-windows\_resize.txt" -Value "NOT_RUNNING" -Encoding UTF8; exit }
$h = $p.MainWindowHandle

$r0 = New-Object RECT
[void][W]::GetWindowRect($h, [ref]$r0)
$out += "ORIG_PHYS=$($r0.Right-$r0.Left)x$($r0.Bottom-$r0.Top)"

function Shot([string]$name) {
  $r = New-Object RECT
  [void][W]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $dc = $g.GetHdc()
  [void][W]::PrintWindow($h, $dc, 2)
  $g.ReleaseHdc($dc); $g.Dispose()
  $bmp.Save("E:\celechron-windows\$name", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# --- narrow: 600 logical wide = 1200 physical (below the 700 breakpoint) ---
[void][W]::MoveWindow($h, $r0.Left, $r0.Top, 1200, 1500, $true)
Start-Sleep -Seconds 3
$out += "NARROW_PHYS=1200x1500 (logical 600x750, below 700 breakpoint)"
Shot "_narrow.png"

# --- restore ---
[void][W]::MoveWindow($h, $r0.Left, $r0.Top, ($r0.Right-$r0.Left), ($r0.Bottom-$r0.Top), $true)
Start-Sleep -Seconds 2
$r = New-Object RECT
[void][W]::GetWindowRect($h, [ref]$r)
$out += "RESTORED_PHYS=$($r.Right-$r.Left)x$($r.Bottom-$r.Top)"

# --- notification registration: flutter_local_notifications Windows creates a Start Menu shortcut for the AUMID ---
$out += "--- Start Menu shortcuts (find the AUMID registration) ---"
$menus = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
foreach ($m in $menus) {
  Get-ChildItem $m -Recurse -Include *.lnk -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Celechron' } |
    ForEach-Object { $out += $_.FullName }
}
$out += "--- protocol registry (celechron://) ---"
if (Test-Path "HKCU:\Software\Classes\celechron") { $out += "HKCU celechron:// REGISTERED" } else { $out += "HKCU celechron:// not registered (expected before install)" }

Set-Content "E:\celechron-windows\_resize.txt" -Value $out -Encoding UTF8
