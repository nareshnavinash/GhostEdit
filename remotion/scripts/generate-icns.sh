#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
ICONSET="$OUT/icns/AppIcon.iconset"

echo "==> Generating macOS .icns from idle icons..."

mkdir -p "$ICONSET"

# Map PNG sizes to .iconset naming convention
cp "$OUT/icons/idle/icon_16x16.png"     "$ICONSET/icon_16x16.png"
cp "$OUT/icons/idle/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$OUT/icons/idle/icon_32x32.png"     "$ICONSET/icon_32x32.png"
cp "$OUT/icons/idle/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$OUT/icons/idle/icon_128x128.png"   "$ICONSET/icon_128x128.png"
cp "$OUT/icons/idle/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$OUT/icons/idle/icon_256x256.png"   "$ICONSET/icon_256x256.png"
cp "$OUT/icons/idle/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$OUT/icons/idle/icon_512x512.png"   "$ICONSET/icon_512x512.png"
cp "$OUT/icons/idle/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT/icns/AppIcon.icns"

# Clean up the .iconset folder
rm -rf "$ICONSET"

echo "==> Created $OUT/icns/AppIcon.icns"
file "$OUT/icns/AppIcon.icns"
