#!/bin/zsh
# Too Much Chrome 开发启动脚本（日常用）
# 用法：
#   ./launch.sh          构建 + 启动 GUI（开发模式，adhoc 签名）
#   ./launch.sh cli      运行无头扫描 CLI（tmc-scan）
# 对外分发（签名/公证/DMG）请用 scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-gui}" == "cli" ]]; then
  swift build --product tmc-scan
  exec ./.build/debug/tmc-scan
fi

exec ./scripts/build-app.sh dev
