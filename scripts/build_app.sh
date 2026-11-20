#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
APP="$DIST/Sideleaf.app"
ICON_SOURCE="$ROOT/../flomo_ios/Flomo/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

cd "$ROOT"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "找不到源图标：$ICON_SOURCE" >&2
  exit 1
fi

ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "→ 编译 release"
swift build -c release --disable-sandbox \
  -Xswiftc -Xfrontend -Xswiftc -disable-sandbox

BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"

echo "→ 组装 Sideleaf"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FlomoMac" "$APP/Contents/MacOS/Sideleaf"
chmod +x "$APP/Contents/MacOS/Sideleaf"
cp "$ROOT/Sources/FlomoMac/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ 临时签名"
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "→ 清除隔离标记"
xattr -cr "$APP" || true

echo "✓ 完成：$APP"
du -sh "$APP"
