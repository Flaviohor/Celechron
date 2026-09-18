#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""打包 Pcelechron 的 Windows x64 发行包。

产出：
  dist/Pcelechron-<ver>-windows-x64-portable.zip   绿色便携版（解压即用）

要点：Pcelechron.exe 依赖 VC++ 运行时（MSVCP140 / VCRUNTIME140），
目标机器没装会直接启动失败。这里从 VS 的可再发行目录取官方 CRT 文件
做 app-local 部署，包内自带，不再依赖装机环境（Windows 官方支持的部署方式）。
"""

import os
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(r"E:\celechron-windows")
BUILD = ROOT / "build" / "windows" / "x64" / "runner" / "Release"
DIST = ROOT / "dist"

APP_NAME = "Pcelechron"
APP_VERSION = "1.3.3"

# 需要的 CRT 文件（app-local 部署）
CRT_FILES = [
    "msvcp140.dll",
    "msvcp140_1.dll",
    "msvcp140_2.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "concrt140.dll",
]

# 构建产物里的无关目录
EXCLUDE_DIRS = {"NVIDIA Corporation"}


def find_crt_dir():
    """在 Visual Studio 安装目录里找官方可再发行 CRT。"""
    import glob
    pats = [
        r"E:\Program Files\Microsoft Visual Studio\2022\**\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT",
        r"C:\Program Files\Microsoft Visual Studio\2022\**\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT",
        r"C:\Program Files (x86)\Microsoft Visual Studio\2022\**\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT",
    ]
    for pat in pats:
        hits = sorted(glob.glob(pat, recursive=True))
        if hits:
            return Path(hits[-1])
    return None


def copy_tree(src: Path, dst: Path):
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        if item.is_dir():
            if item.name in EXCLUDE_DIRS:
                continue
            copy_tree(item, dst / item.name)
        else:
            shutil.copy2(item, dst / item.name)


def dir_size(p: Path) -> int:
    total = 0
    for r, _d, fs in os.walk(p):
        for f in fs:
            try:
                total += (Path(r) / f).stat().st_size
            except OSError:
                pass
    return total


def main():
    if not (BUILD / f"{APP_NAME}.exe").exists():
        print(f"[x] 找不到构建产物: {BUILD / (APP_NAME + '.exe')}")
        print("    先跑 ./tool/build.sh")
        return 1

    name = f"{APP_NAME}-{APP_VERSION}-windows-x64"
    stage = DIST / name

    print(f"[1/4] 清理 dist/")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)

    print(f"[2/4] 拷贝构建产物 -> {stage.name}/")
    copy_tree(BUILD, stage)

    print(f"[3/4] 部署 VC++ 运行时（app-local）")
    crt = find_crt_dir()
    if crt is None:
        print("[!] 未找到 VS 可再发行 CRT，跳过（目标机器需自行安装 VC++ 运行库）")
    else:
        print(f"    来源: {crt}")
        for f in CRT_FILES:
            s = crt / f
            if s.exists():
                shutil.copy2(s, stage / f)
                print(f"    + {f:24s} {s.stat().st_size:>9,} B")
            else:
                print(f"    - {f:24s} 缺失，跳过")

    readme = stage / "使用说明.txt"
    readme.write_text(
        f"""{APP_NAME} {APP_VERSION} — Windows x64 便携版
================================================

【运行】
  双击 {APP_NAME}.exe 即可，无需安装。

【目录说明】
  {APP_NAME}.exe          主程序
  flutter_windows.dll     Flutter 引擎（必需，勿删）
  data\\                  应用资源与 AOT 快照（必需，勿删）
  msvcp140.dll 等        VC++ 运行时，已随包提供，目标机器无需另装
  *_plugin.dll           各功能插件（通知 / 分享 / 深链 / 安全存储）

【数据存放位置】
  数据库（Hive）：C:\\Users\\<用户名>\\Documents\\ 下的 db*.hive
  诊断日志：%TEMP%\\pcelechron_diagnostic_logs\\
  刷新锁：  %TEMP%\\pcelechron_refresh_locks\\
  卸载或迁移前请备份上述文件。

【已知限制】
  · 桌面端的后台刷新是「应用内定时器」，程序关掉就不会自动刷新；
    成绩推送 / DDL 提醒只在程序运行时生效。移动端是系统级调度，语义不同。
  · 系统日历同步依赖 device_calendar（仅 Android/iOS 有实现），
    桌面端已改为引导使用 .ics 日历导出。
  · celechron:// 深链协议需要安装器写注册表；便携版未注册，付款码页面
    请从应用内进入。安装版会一并注册。
  · 首次运行若弹出 SmartScreen 提示，是因为未做代码签名，
    选「更多信息 → 仍要运行」即可。

【系统要求】
  Windows 10 1809 (17763) 或更高，x64。
""",
        encoding="utf-8",
    )

    print(f"[4/4] 压缩为 zip")
    zip_path = DIST / f"{name}-portable.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for r, _d, fs in os.walk(stage):
            for f in fs:
                full = Path(r) / f
                z.write(full, Path(name) / full.relative_to(stage))
    print(f"    -> {zip_path.name}  {zip_path.stat().st_size / 1048576:.1f} MB")

    print()
    print("=" * 56)
    print(f"  暂存目录  {stage}")
    print(f"  目录大小  {dir_size(stage) / 1048576:.1f} MB")
    print(f"  压缩包    {zip_path}")
    print("=" * 56)
    return 0


if __name__ == "__main__":
    sys.exit(main())
