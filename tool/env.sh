#!/usr/bin/env bash
# Celechron Windows 移植 —— 构建环境
#
# 用法：source tool/env.sh
#
# 注意（踩过的坑）：
#   PUB_CACHE 必须用「正斜杠」。MSYS/Git Bash 会把 `E:\pub-cache` 这类反斜杠
#   Windows 路径改写成 `E://pub-cache`，而 git 会把 `E://` 当成 URL scheme，
#   报 "git: 'remote-E' is not a git command" 然后依赖解析失败。

export FLUTTER_ROOT="E:/flutter"
# PATH 必须用 MSYS 风格（/e/...）。若写成 `E:/flutter/bin`，那个冒号会被 bash
# 当成 PATH 分隔符，PATH 直接被切成 "E" 和 "/flutter/bin" 两段，flutter 找不到。
export PATH="/e/flutter/bin:$PATH"

# 国内镜像：pub 包与 Flutter 引擎产物都走这里，无需梯子
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# 正斜杠！见文件头注释
export PUB_CACHE="E:/pub-cache"

# Flutter SDK 来自 zip 包，本地没有可用的 GitHub 远端。
# 版本检查会去 `git fetch --tags` 并卡住 ~21 秒，直接关掉。
export FLUTTER_SUPPRESS_ANALYTICS=true

cd "$(dirname "${BASH_SOURCE[0]}")/.." || return 1
