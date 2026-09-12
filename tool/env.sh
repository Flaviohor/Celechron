#!/usr/bin/env bash
# Celechron Windows 移植 —— 构建环境
#
# 用法：source tool/env.sh  然后调用 flutterx 而不是 flutter
#   flutterx build windows --debug
#   flutterx analyze
#
# 或者直接用 ./tool/build.sh / ./tool/run.sh，它们已经包好了。

export FLUTTER_ROOT="E:/flutter"
# PATH 必须用 MSYS 风格（/e/...）。若写成 `E:/flutter/bin`，那个冒号会被 bash
# 当成 PATH 分隔符，PATH 直接被切成 "E" 和 "/flutter/bin" 两段，flutter 找不到。
export PATH="/e/flutter/bin:$PATH"

# 国内镜像：pub 包与 Flutter 引擎产物都走这里，无需梯子
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# 正斜杠！MSYS/Git Bash 会把 `E:\pub-cache` 这类反斜杠 Windows 路径改写成
# `E://pub-cache`，而 git 会把 `E://` 当成 URL scheme，报
# "git: 'remote-E' is not a git command" 然后依赖解析失败。
export PUB_CACHE="E:/pub-cache"

export FLUTTER_SUPPRESS_ANALYTICS=true

# ---------------------------------------------------------------------------
# Windows 标准环境变量注入
#
# 本会话里 ProgramFiles / PROGRAMFILES(X86) 全部丢失（`env | grep -i programfiles`
# 一条都没有），而 flutter 定位 vswhere.exe 时必须读 PROGRAMFILES(X86)：
#     flutter_tools/lib/src/windows/visual_studio.dart:264
#     throwToolExit('%$programFilesEnv% environment variable not found.');
#
# bash 不允许 export 名字里带括号的变量，只能在启动子进程时用 env 注入，
# 所以这里包一个 flutterx 而不是直接改 flutter 的调用。
#
# 值一律用正斜杠 —— 反斜杠会被 MSYS 改写成双斜杠（同 PUB_CACHE 那个坑）。
# ---------------------------------------------------------------------------
export PROGRAMFILES="C:/Program Files"
export ProgramFiles="C:/Program Files"
export ProgramW6432="C:/Program Files"

flutterx() {
  env "PROGRAMFILES=C:/Program Files" \
    "ProgramFiles=C:/Program Files" \
    "ProgramW6432=C:/Program Files" \
    "PROGRAMFILES(X86)=C:/Program Files (x86)" \
    "ProgramFiles(x86)=C:/Program Files (x86)" \
    flutter --no-version-check "$@"
}

cd "$(dirname "${BASH_SOURCE[0]}")/.." || return 1
