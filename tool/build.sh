#!/usr/bin/env bash
# 构建 Windows 版本。
#
#   ./tool/build.sh            # release
#   ./tool/build.sh --debug    # debug
#
# 只需要一个前置条件：安装 Visual Studio 2022，并勾选「使用 C++ 的桌面开发」
# 工作负载。**不需要开启开发者模式** —— 插件链接由 tool/link_plugins.dart
# 用目录联接（junction）生成，见 WINDOWS_PORT.md。

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source tool/env.sh

# 每个插件都要在 <platform>/flutter/ephemeral/.plugin_symlinks/ 下有一个链接，
# 否则 flutter 会自己建符号链接 —— 那需要开发者模式或管理员权限。
dart tool/link_plugins.dart

flutterx build windows "$@"

echo
echo "构建产物：build/windows/x64/runner/Release/Pcelechron.exe"
