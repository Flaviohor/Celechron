#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PCelechron 字体子集化工具

为什么：
  HarmonyOS Sans SC 完整 6 字重 × ~8MB = 47MB，分发包很大。
  实际 UI 只用到 ~ 几千个汉字 + ASCII + 标点。

策略：
  1. 扫 lib/、test/、assets/、pubspec.yaml、README.md 等所有文本源
     收集「实际渲染过的 Unicode codepoint」集合 A。
  2. 加上一份「基础拉丁 + 中文常用标点 + 0-9 + a-zA-Z」安全垫集合 B
     （防止有人输入我们没扫到的字时字体掉成豆腐块）。
  3. 用 pyftsubset 把每个 .ttf 子集到 A ∪ B。
  4. 输出到 fonts/ 下原文件名，Flutter 端无需任何改动（pubspec.yaml
     用通配符 fonts/HarmonyOS_Sans_*.ttf，子集后照常加载）。

用法：
  python tool/subset_fonts.py            # 跑全部 6 个
  python tool/subset_fonts.py --dry-run  # 只扫描并报告字符集，不动字体
  python tool/subset_fonts.py --report   # 输出字符集报告到 build/font-chars.txt
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONTS_DIR = ROOT / "fonts"

# 安全垫：哪怕项目里没用到，也要保留下来的字符
# - ASCII 可见字符 + 数字 + 拉丁扩展
# - 通用中文标点（CJK 标点 / 全角空格 / 中文括号等）
# - 几个常见 emoji 之外的字符占位（不含 emoji 字形，避免 1MB+ 的 apple color emoji）
SAFETY_PAD = (
    " !\"#$%&'()*+,-./"  # ASCII 标点
    "0123456789"
    ":;<=>?@[\\]^_`{|}~"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    " ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿"
    "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß"
    "àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ"
    "　、。·ˉˇ¨〃々—～‖…‰※℃℅℉™"
    "！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？［＼］＾＿｀"
    "｛｜｝～"
    "￠￡￢￣￤"
    "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ"
    "αβγδεζηθικλμνξοπρστυφχψω"
    "←→↑↓↖↗↘↙"
    "─━│┃┄┅┆┇┈┉┊┋┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟"
    "┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿"
    "╀╁╂╃╄╅╆╇╈╉╊╋"
    "■□▢▣▤▥▦▧▨▩▪▫▬▭▮▯▰▱▲△▴▵▶▷▸▹►▻▼▽▾▿"
    "◀◁◂◃◄◅◆◇◈◉◊○◌◍◎●◐◑◒◓◔◕◖◗◘◙◚◛◜◝◞◟"
    "◠◡◢◣◤◥◦◧◨◩◪◫◬◭◮◯◰◱◲◳◴◵◶◷◸◹◺◻◼◽◾◿"
)


def collect_chars_from_files(scan_roots: list[Path]) -> set[str]:
    chars: set[str] = set()
    skipped = []
    for root in scan_roots:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix.lower() in {
                ".ttf", ".otf", ".woff", ".woff2",  # 字体本身别扫
                ".png", ".jpg", ".jpeg", ".gif", ".ico",  # 图片
                ".zip", ".7z", ".tar", ".gz",
                ".lock", ".dill",
            }:
                # 锁文件 / 字体 / 二进制 / 压缩包 都跳过
                # 扩展名按需再补
                continue
            try:
                # 用二进制读 + utf-8 解码，避免 GBK / Latin-1 文件炸掉
                data = p.read_bytes()
                text = data.decode("utf-8", errors="ignore")
                chars.update(text)
            except OSError as exc:
                skipped.append((p, str(exc)))
    if skipped:
        print(f"  [warn] {len(skipped)} files skipped (read errors):")
        for p, msg in skipped[:5]:
            print(f"         {p.relative_to(ROOT)}: {msg}")
        if len(skipped) > 5:
            print(f"         ... and {len(skipped) - 5} more")
    return chars


def scan_report(chars: set[str]) -> None:
    n_total = len(chars)
    n_ascii = sum(1 for c in chars if ord(c) < 0x80)
    n_cjk = sum(1 for c in chars if 0x4E00 <= ord(c) <= 0x9FFF)
    n_cjk_ext = sum(1 for c in chars if 0x3400 <= ord(c) <= 0x4DBF)
    n_other = n_total - n_ascii - n_cjk - n_cjk_ext
    print(f"  Unique chars  : {n_total}")
    print(f"    ASCII       : {n_ascii}")
    print(f"    CJK 基本    : {n_cjk}")
    print(f"    CJK 扩展A   : {n_cjk_ext}")
    print(f"    其他        : {n_other}")


def subset_one(src: Path, dst: Path, chars: str) -> tuple[int, int]:
    """子集化一个字体；返回 (输入字节, 输出字节)。"""
    from fontTools.subset import Subsetter, Options
    from fontTools.ttLib import TTFont

    # 先量输入大小（写完会变）
    in_bytes = src.stat().st_size

    font = TTFont(str(src), recalcBBoxes=False, recalcTimestamp=False)
    options = Options()
    options.flavor = "woff2"  # 无 flavor 标记则保持 TTF
    options.desubroutinize = True
    options.hinting = False
    options.notdef_glyph = True
    options.notdef_outline = True
    options.layout_features = ["*"]  # 保留所有 OTL 表
    options.name_IDs = ["*"]  # 保留 name 表的全部记录
    options.drop_tables += ["DSIG", "LTSH"]  # 微软过时的 hash 表 + 线性阈值表
    options.legacy_cmap = True
    options.symbol_cmap = False
    options.prune_unicode_ranges = True
    options.recalc_bounds = False
    options.recalc_timestamp = False

    subsetter = Subsetter(options=options)
    subsetter.populate(text=chars)
    subsetter.subset(font)

    # 写出
    font.flavor = None  # 保留 TTF 容器（pubspec 用 .ttf）
    font.save(str(dst))

    return in_bytes, dst.stat().st_size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只扫描字符集，不动字体")
    parser.add_argument("--report", action="store_true", help="把字符集写出到 build/font-chars.txt")
    args = parser.parse_args()

    if not FONTS_DIR.exists():
        print(f"fonts 目录不存在：{FONTS_DIR}", file=sys.stderr)
        return 1

    print(f"Project root  : {ROOT}")
    print(f"Fonts dir     : {FONTS_DIR}")

    scan_roots = [ROOT / "lib", ROOT / "test", ROOT / "assets"]
    # 顶层几个文本文件
    for top in ["pubspec.yaml", "README.md", "WINDOWS_PORT.md", "LICENSE"]:
        p = ROOT / top
        if p.exists():
            scan_roots.append(p)

    print(f"\n[1/3] 扫描字符集 ...")
    chars = collect_chars_from_files(scan_roots)
    chars.update(SAFETY_PAD)
    scan_report(chars)

    if args.report:
        report_path = ROOT / "build" / "font-chars.txt"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text("".join(sorted(chars)), encoding="utf-8")
        print(f"  Report        : {report_path.relative_to(ROOT)} ({len(chars)} chars)")

    if args.dry_run:
        print("\n  --dry-run 模式下不动字体。")
        return 0

    # 备份
    backup_dir = ROOT / "fonts" / "_unsorted.bak"
    if not backup_dir.exists():
        backup_dir.mkdir()
        for f in FONTS_DIR.glob("*.ttf"):
            (backup_dir / f.name).write_bytes(f.read_bytes())
        print(f"\n  Backup        : {backup_dir.relative_to(ROOT)}/{'*.ttf'}")

    # 子集化每个 .ttf
    print(f"\n[2/3] 子集化 ...")
    chars_text = "".join(sorted(chars))
    total_in = total_out = 0
    for src in sorted(FONTS_DIR.glob("HarmonyOS_Sans_*.ttf")):
        if src.parent.name == "_unsorted.bak":
            continue
        dst = src  # 原地覆盖
        try:
            in_bytes, out_bytes = subset_one(src, dst, chars_text)
        except Exception as exc:
            print(f"  [FAIL] {src.name}: {exc}")
            return 1
        total_in += in_bytes
        total_out += out_bytes
        ratio = (1 - out_bytes / in_bytes) * 100 if in_bytes else 0
        print(
            f"  {src.name:<28} "
            f"{in_bytes / 1e6:6.2f} MB -> {out_bytes / 1e6:6.2f} MB  "
            f"({ratio:5.1f}% smaller)"
        )

    print(f"\n[3/3] 总计：{total_in / 1e6:.1f} MB -> {total_out / 1e6:.1f} MB "
          f"((1 - {total_out / total_in:.0%}) saved)")

    # 把 .gitignore 之类忽略一下，避免备份也进版本控制
    gitignore = ROOT / "fonts" / ".gitignore"
    if not gitignore.exists():
        gitignore.write_text("_unsorted.bak/\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())