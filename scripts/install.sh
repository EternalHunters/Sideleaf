#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Sideleaf.app"

"$ROOT/scripts/build_app.sh"

TARGET_DIR="$HOME/Applications"
if [[ -w /Applications ]]; then
  TARGET_DIR="/Applications"
fi
TARGET="$TARGET_DIR/Sideleaf.app"
mkdir -p "$TARGET_DIR"

# 只退出 Sideleaf 的进程。
pkill -f "$TARGET/Contents/MacOS/Sideleaf" >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/Sideleaf" >/dev/null 2>&1 || true
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
xattr -cr "$TARGET" || true

echo "✓ 已安装到 $TARGET"
open "$TARGET"
