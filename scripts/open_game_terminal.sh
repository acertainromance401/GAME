#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
GAME_BIN="$BUILD_DIR/game_tui"

if [[ ! -x "$GAME_BIN" ]]; then
  echo "game_tui 실행 파일이 없습니다. 먼저 빌드하세요:"
  echo "  cmake -S . -B build -DGAME_USE_FTXUI=ON"
  echo "  cmake --build build"
  exit 1
fi

osascript <<EOF
 tell application "Terminal"
     activate
   do script "cd '$ROOT_DIR' && '$GAME_BIN'"
   set bounds of front window to {40, 40, 1620, 1120}
 end tell
EOF
