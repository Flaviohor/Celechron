#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 Windows 内置的 IExpress + 7-Zip 生成单文件安装器 PCelechron-Setup.exe。

为什么不用 Inno Setup：本机未安装，且当前网络下从 GitHub 拉 10MB 安装包
屡次被代理截断。IExpress 是 Windows 自带的自解压打包器，配合 7-Zip 的
LZMA2 压缩，同样能产出单个 Setup.exe。

整体结构：
    IExpress 包（扁平，无子目录 —— IExpress 对子目录支持不可靠）
      ├── PCelechron.7z    整个应用（含 VC++ 运行时 DLL）
      ├── 7z.exe / 7z.dll 解压用
      ├── install.cmd     入口（ASCII，转调 PowerShell）
      ├── install.ps1     实际安装逻辑（UTF-8 BOM，可写中文）
      └── uninstall.ps1   卸载逻辑

产出：dist/PCelechron-<ver>-windows-x64-setup.exe
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"E:\celechron-windows")
DIST = ROOT / "dist"
STAGE_APP = DIST / "PCelechron-PC-1.0.0-windows-x64"

SEVENZIP_DIR = Path(r"E:\7-Zip")
SEVENZIP_EXE = SEVENZIP_DIR / "7z.exe"
SEVENZIP_DLL = SEVENZIP_DIR / "7z.dll"

IEXPRESS = Path(r"C:\Windows\System32\iexpress.exe")

APP_NAME = "PCelechron"
APP_VERSION = "PC-1.0.0"
PACK_NAME = "celechron-iexpress-stage"
SETUP_BASENAME = f"{APP_NAME}-{APP_VERSION}-windows-x64-setup"

# --------------------------------------------------------------------------
# install.cmd —— 保持纯 ASCII。IExpress 的 AppLaunched 走 cmd 时，
# 非 ASCII 内容会因为代码页差异出问题，所以中文一律放 PowerShell 里。
# --------------------------------------------------------------------------
INSTALL_CMD = """@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
exit /b %ERRORLEVEL%
"""

# --------------------------------------------------------------------------
# install.ps1 —— 以 UTF-8 BOM 保存，PowerShell 5.1 才能正确读出中文
# --------------------------------------------------------------------------
INSTALL_PS1 = r"""$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$appName = 'PCelechron'
$version = 'PC-1.0.0'
# 不要用 $env:LOCALAPPDATA / $env:APPDATA —— 环境变量可能被裁剪掉（实测过 APPDATA 为空），
# GetFolderPath 走 Shell API，任何时候都可靠。
$target = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\PCelechron'
$logFile = Join-Path ([IO.Path]::GetTempPath()) 'pcelechron-install.log'
$log = New-Object System.Collections.Generic.List[string]

function Say($m) {
  $log.Add($m)
  Write-Host $m
}

function Fail($m) {
  Say ("[失败] " + $m)
  $log -join "`r`n" | Set-Content -Path $logFile -Encoding UTF8
  $ws = New-Object -ComObject WScript.Shell
  $ws.Popup("PCelechron 安装失败：`r`n`r`n" + $m + "`r`n`r`n详细信息见：`r`n" + $logFile, 0, "PCelechron 安装程序", 16) | Out-Null
  exit 1
}

try {
  Say ("PCelechron " + $version + " 安装开始  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

  # 已安装的旧版本可能在运行，文件会被占用
  if (Get-Process -Name $appName -ErrorAction SilentlyContinue) {
    Say "检测到 PCelechron 正在运行，先关闭它"
    Get-Process -Name $appName -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
  }

  Say ("[1/5] 解压程序文件到 " + $target)
  if (-not (Test-Path $src)) { Fail "解压目录不存在" }
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  $sevenZip = Join-Path $src '7z.exe'
  $payload = Join-Path $src ($appName + '.7z')
  if (-not (Test-Path $sevenZip)) { Fail "找不到 7z.exe" }
  if (-not (Test-Path $payload)) { Fail "找不到 " + $payload }
  & $sevenZip x $payload ("-o" + $target) -y -bso0 -bsp0 | Out-Null
  $exePath = Join-Path $target ($appName + '.exe')
  if (-not (Test-Path $exePath)) { Fail ("解压后找不到 " + $exePath + "，压缩包可能损坏") }
  Say "      完成"

  Say "[2/5] 创建快捷方式"
  $ws = New-Object -ComObject WScript.Shell
  $startMenu = [Environment]::GetFolderPath('Programs')
  if ($startMenu -and (Test-Path $startMenu)) {
    $lnk = $ws.CreateShortcut((Join-Path $startMenu ($appName + '.lnk')))
    $lnk.TargetPath = $exePath
    $lnk.WorkingDirectory = $target
    $lnk.IconLocation = $exePath + ',0'
    $lnk.Description = 'PCelechron 课程表与学业助手'
    $lnk.Save()
    Say "      开始菜单"
  }
  $desktop = [Environment]::GetFolderPath('Desktop')
  if ($desktop) {
    $lnk2 = $ws.CreateShortcut((Join-Path $desktop ($appName + '.lnk')))
    $lnk2.TargetPath = $exePath
    $lnk2.WorkingDirectory = $target
    $lnk2.IconLocation = $exePath + ',0'
    $lnk2.Description = 'PCelechron 课程表与学业助手'
    $lnk2.Save()
    Say "      桌面"
  }

  Say "[3/5] 注册 celechron:// 深链协议"
  $proto = 'HKCU:\Software\Classes\celechron'
  New-Item -Path $proto -Force | Out-Null
  Set-ItemProperty -Path $proto -Name '(default)' -Value 'URL:Celechron Protocol'
  New-ItemProperty -Path $proto -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
  New-Item -Path ($proto + '\DefaultIcon') -Force | Out-Null
  Set-ItemProperty -Path ($proto + '\DefaultIcon') -Name '(default)' -Value ($exePath + ',0')
  New-Item -Path ($proto + '\shell\open\command') -Force | Out-Null
  Set-ItemProperty -Path ($proto + '\shell\open\command') -Name '(default)' -Value ('"' + $exePath + '" "%1"')
  Say "      已写入 HKCU\Software\Classes\celechron"

  Say "[4/5] 注册卸载项"
  $uninstaller = Join-Path $src 'uninstall.ps1'
  if (Test-Path $uninstaller) {
    Copy-Item $uninstaller (Join-Path $target 'uninstall.ps1') -Force
  }
  $un = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Celechron'
  New-Item -Path $un -Force | Out-Null
  Set-ItemProperty -Path $un -Name 'DisplayName'     -Value ('PCelechron ' + $version)
  Set-ItemProperty -Path $un -Name 'DisplayVersion'  -Value $version
  Set-ItemProperty -Path $un -Name 'Publisher'       -Value 'PCelechron contributors'
  Set-ItemProperty -Path $un -Name 'InstallLocation' -Value $target
  Set-ItemProperty -Path $un -Name 'DisplayIcon'     -Value $exePath
  Set-ItemProperty -Path $un -Name 'UninstallString' -Value ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $target 'uninstall.ps1') + '"')
  New-ItemProperty -Path $un -Name 'NoModify' -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $un -Name 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null
  Say "      已注册到「应用和功能」"

  Say "[5/5] 启动 PCelechron"
  Start-Process -FilePath $exePath -WorkingDirectory $target

  Say "安装完成"
  $log -join "`r`n" | Set-Content -Path $logFile -Encoding UTF8
} catch {
  Fail ($_.Exception.Message)
}
"""

# --------------------------------------------------------------------------
# uninstall.ps1
#
# 自删除的处理：先把自身复制到 %TEMP% 并以 -Worker 重启，
# 由临时副本负责删掉安装目录，避免「正在执行的脚本删自己所在目录」。
#
# 注意：不删除用户的数据库（在「文档」目录下）。这是用户数据，
# 卸载程序不应擅自清理，只在结束时告知位置。
# --------------------------------------------------------------------------
UNINSTALL_PS1 = r"""param([switch]$Worker)

$appName = 'PCelechron'
$target = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\PCelechron'
$proto = 'HKCU:\Software\Classes\celechron'
$unkey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Celechron'

if ($Worker) {
  Start-Sleep -Seconds 2
  Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
  exit 0
}

Stop-Process -Name $appName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800

$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) ($appName + '.lnk')
Remove-Item $startMenu -Force -ErrorAction SilentlyContinue
$desktop = [Environment]::GetFolderPath('Desktop')
if ($desktop) { Remove-Item (Join-Path $desktop ($appName + '.lnk')) -Force -ErrorAction SilentlyContinue }

Remove-Item $proto -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $unkey -Recurse -Force -ErrorAction SilentlyContinue

$tmp = Join-Path ([IO.Path]::GetTempPath()) 'pcelechron-uninstall-worker.ps1'
Copy-Item $PSCommandPath $tmp -Force
Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"'), '-Worker') -WindowStyle Hidden

$docs = [Environment]::GetFolderPath('MyDocuments')
$msg = "PCelechron 已卸载。`r`n`r`n你的数据仍然保留在：`r`n" + $docs + "`r`n" + `
       "（dbuser.hive、dboptions.hive 等）`r`n`r`n如需彻底清理请手动删除这些文件。"
$ws = New-Object -ComObject WScript.Shell
$ws.Popup($msg, 0, 'PCelechron 卸载', 64) | Out-Null
"""


def log(m):
    print(m, flush=True)


def build_payload(stage_dir: Path) -> Path:
    """把暂存的应用目录压成 PCelechron.7z。"""
    out = stage_dir / f"{APP_NAME}.7z"
    if out.exists():
        out.unlink()
    log(f"[1/6] 压缩应用载荷 -> {out.name}")
    cmd = [
        str(SEVENZIP_EXE), "a", "-t7z", "-mx=9", "-mmt=on",
        str(out), str(STAGE_APP / "*"),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if r.returncode != 0 or not out.exists():
        log(r.stdout[-2000:])
        log(r.stderr[-2000:])
        raise SystemExit("7z 压缩失败")
    log(f"      {out.stat().st_size / 1048576:.1f} MB")
    return out


def write_text(path: Path, text: str, encoding: str, newline: str = "\r\n"):
    # 统一成 CRLF，脚本在 Windows 上更稳
    data = text.replace("\r\n", "\n").replace("\n", newline)
    with open(path, "w", encoding=encoding, newline="") as f:
        f.write(data)
    log(f"      + {path.name}  ({path.stat().st_size} B)")


def build_sed(stage_dir: Path, files, out_setup: Path) -> Path:
    lines = [
        "[Version]",
        "Class=IEXPRESS",
        "SEDVersion=3",
        "[Options]",
        "PackagePurpose=InstallApp",
        "ShowInstallProgramWindow=1",
        "HideExtractAnimation=1",
        "UseLongFileName=1",
        "InsideCompressed=0",
        "CAB_FixedSize=0",
        "CAB_ResvCodeSigning=0",
        "RebootMode=N",
        "InstallPrompt=",
        "DisplayLicense=",
        "FinishMessage=",
        f"TargetName={out_setup}",
        f"FriendlyName={APP_NAME} {APP_VERSION} Setup",
        "AppLaunched=install.cmd",
        "PostInstallCmd=<None>",
        "AdminQuietInstCmd=",
        "UserQuietInstCmd=",
        "SourceFiles=SourceFiles",
        "[Strings]",
    ]
    for i, f in enumerate(files):
        lines.append(f'FILE{i}="{f.name}"')
    lines += [
        "[SourceFiles]",
        f"SourceFiles0={stage_dir}\\",
        "[SourceFiles0]",
    ]
    for i in range(len(files)):
        lines.append(f"%FILE{i}%=")
    lines.append("")

    sed = stage_dir.parent / "installer.sed"
    # SED 必须是 ASCII/ANSI，不能有 BOM
    sed.write_text("\r\n".join(lines), encoding="ascii", newline="")
    log(f"      + {sed.name}")
    return sed


def main():
    if not (STAGE_APP / f"{APP_NAME}.exe").exists():
        log(f"[x] 找不到暂存应用目录：{STAGE_APP}")
        log("    先跑 tool/package.py")
        return 1
    for p in (SEVENZIP_EXE, SEVENZIP_DLL, IEXPRESS):
        if not p.exists():
            log(f"[x] 缺少依赖：{p}")
            return 1

    stage = DIST / PACK_NAME
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    log(f"构建目录 {stage}")

    payload = build_payload(stage)

    log("[2/6] 拷贝解压工具")
    shutil.copy2(SEVENZIP_EXE, stage / "7z.exe")
    shutil.copy2(SEVENZIP_DLL, stage / "7z.dll")
    log(f"      + 7z.exe  {(stage / '7z.exe').stat().st_size:,} B")
    log(f"      + 7z.dll  {(stage / '7z.dll').stat().st_size:,} B")

    log("[3/6] 写入安装/卸载脚本")
    write_text(stage / "install.cmd", INSTALL_CMD, "ascii")
    # utf-8-sig = 带 BOM，PowerShell 5.1 靠 BOM 识别 UTF-8
    write_text(stage / "install.ps1", INSTALL_PS1, "utf-8-sig")
    write_text(stage / "uninstall.ps1", UNINSTALL_PS1, "utf-8-sig")

    log("[4/6] 生成 IExpress 描述文件")
    files = [
        stage / f"{APP_NAME}.7z",
        stage / "7z.exe",
        stage / "7z.dll",
        stage / "install.cmd",
        stage / "install.ps1",
        stage / "uninstall.ps1",
    ]
    out_setup = DIST / f"{SETUP_BASENAME}.exe"
    if out_setup.exists():
        out_setup.unlink()
    sed = build_sed(stage, files, out_setup)

    log("[5/6] 调用 IExpress 打包（约 1-2 分钟）")
    r = subprocess.run(
        [str(IEXPRESS), "/N", "/Q", str(sed)],
        capture_output=True, text=True, errors="replace",
    )
    if r.returncode != 0:
        log(f"      iexpress exit={r.returncode}")
        log(r.stdout[-1500:]); log(r.stderr[-1500:])

    # IExpress 是异步写文件的，等它落盘
    import time
    for _ in range(60):
        if out_setup.exists() and out_setup.stat().st_size > 1024:
            break
        time.sleep(1)

    log("[6/6] 校验产物")
    if not out_setup.exists():
        log("[x] 安装器未生成")
        return 1
    size = out_setup.stat().st_size
    if size < 1024:
        log(f"[x] 安装器大小异常：{size} B")
        return 1

    print()
    print("=" * 60)
    print(f"  安装器   {out_setup}")
    print(f"  大小     {size / 1048576:.1f} MB")
    print(f"  日志     {stage.parent / 'installer.sed'}")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
