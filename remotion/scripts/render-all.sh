#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"

echo "==> Rendering GhostEdit brand assets..."

# Clean output
rm -rf "$OUT"
mkdir -p "$OUT/icons/idle" "$OUT/icons/processing" "$OUT/menubar" "$OUT/banners" "$OUT/animated"

# --- App Icons ---
echo "--- App icons (idle) ---"
npx remotion still --config="$ROOT/remotion.config.ts" AppIconIdle "$OUT/icons/idle/icon_1024x1024.png"

echo "--- App icons (processing) ---"
npx remotion still --config="$ROOT/remotion.config.ts" AppIconProcessing "$OUT/icons/processing/icon_1024x1024.png"

# Downscale to standard sizes
for dir in idle processing; do
  for size in 512 256 128 64 32 16; do
    sips -z $size $size "$OUT/icons/$dir/icon_1024x1024.png" --out "$OUT/icons/$dir/icon_${size}x${size}.png" >/dev/null
  done
  echo "    Created 7 sizes for $dir"
done

# --- Menu Bar Icons ---
echo "--- Menu bar icons ---"
npx remotion still --config="$ROOT/remotion.config.ts" MenuBarIconIdle "$OUT/menubar/idle@2x.png"
npx remotion still --config="$ROOT/remotion.config.ts" MenuBarIconProcessing "$OUT/menubar/processing@2x.png"

# Create 1x versions (22x22)
sips -z 22 22 "$OUT/menubar/idle@2x.png" --out "$OUT/menubar/idle.png" >/dev/null
sips -z 22 22 "$OUT/menubar/processing@2x.png" --out "$OUT/menubar/processing.png" >/dev/null
echo "    Created 1x and 2x versions"

# --- Social Banners ---
echo "--- Social banners ---"
npx remotion still --config="$ROOT/remotion.config.ts" TwitterHeader "$OUT/banners/twitter-header.png"
npx remotion still --config="$ROOT/remotion.config.ts" GitHubSocial "$OUT/banners/github-social.png"
npx remotion still --config="$ROOT/remotion.config.ts" OpenGraph "$OUT/banners/open-graph.png"
npx remotion still --config="$ROOT/remotion.config.ts" Generic16x9 "$OUT/banners/generic-16x9.png"

# --- Processing Animation ---
echo "--- Processing animation ---"
npx remotion render --config="$ROOT/remotion.config.ts" ProcessingAnimation "$OUT/animated/processing.mp4"
npx remotion render --config="$ROOT/remotion.config.ts" --image-format=png --codec=gif ProcessingAnimation "$OUT/animated/processing.gif"

echo ""
echo "==> All assets rendered to $OUT/"
echo ""
ls -lR "$OUT/"
