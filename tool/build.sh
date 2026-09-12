#!/usr/bin/env bash
# 构建 Windows 版本。
#
#   ./tool/build.sh            # release
#   ./tool/build.sh --debug    # debug
#
# 前置条件（两个都必须满足，否则 flutter 会直接拒绝构建）：
#   1. Windows 已开启「开发者模式」—— Flutter 需要建符号链接来挂载插件。
#      设置 → 隐私和安全性 → 开发者选项 → 开发人员模式 = 开
#   2. 已安装 Visual Studio 2022，且勾选「使用 C++ 的桌面开发」工作负载。

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source tool/env.sh

flutter --no-version-check build windows "$@"

echo
echo "构建产物：build/windows/x64/runner/Release/Celechron.exe"
