#!/bin/bash
set -e
SRC="assets/AppIcon1024.png"

# --- icon.png (Linux) ---
cp "$SRC" assets/icon.png

# --- icon.icns (macOS) ---
ICONSET="/tmp/ghostedit-icon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
for size in 32 64 256 512 1024; do
  half=$((size / 2))
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${half}x${half}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/icon.icns
rm -rf "$ICONSET"

# --- icon.ico (Windows) ---
# Requires ImageMagick: brew install imagemagick
if command -v convert &>/dev/null; then
  convert "$SRC" -define icon:auto-resize=256,128,64,48,32,16 assets/icon.ico
  echo "Generated assets/icon.ico"
else
  echo "Warning: ImageMagick not found, skipping icon.ico generation"
  echo "Install with: brew install imagemagick"
fi

echo "Icon generation complete!"
