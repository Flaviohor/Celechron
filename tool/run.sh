#!/usr/bin/env bash
# 在桌面直接跑起来（调试用），不用先出安装包。
#
#   ./tool/run.sh
#
# 前置条件同 tool/build.sh（开发者模式 + VS2022 C++ 桌面开发工作负载）。

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source tool/env.sh

flutter --no-version-check run -d windows "$@"
