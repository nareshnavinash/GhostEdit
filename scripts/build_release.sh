#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GhostEdit"
SCHEME="GhostEdit"
PROJECT_PATH="$ROOT_DIR/${APP_NAME}.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
RELEASE_DIR="$ROOT_DIR/build/release"
DMG_STAGING_DIR="$ROOT_DIR/build/dmg"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

# In some environments xcode-select points to CommandLineTools.
# Prefer full Xcode for app builds if available.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$RELEASE_DIR"

cd "$ROOT_DIR"

echo "[1/5] Generating Xcode project"
xcodegen generate --spec project.yml >/dev/null

echo "[2/5] Building macOS release app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build output missing at: $APP_PATH" >&2
  exit 1
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
  STABLE_REQUIREMENT="designated => identifier \"$BUNDLE_IDENTIFIER\""
  echo "[3/5] Signing app (identity: ad-hoc, stable requirement: $BUNDLE_IDENTIFIER)"
  # Keep nested signatures from the build and only re-sign the app wrapper.
  # This avoids ad-hoc cdhash designated requirements that can force TCC re-approval.
  codesign --force --sign - --requirements "=$STABLE_REQUIREMENT" "$APP_PATH"
else
  echo "[3/5] Signing app (identity: $SIGN_IDENTITY)"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"

echo "[4/5] Creating zip artifact"
ZIP_PATH="$RELEASE_DIR/${APP_NAME}-macOS.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[5/5] Creating dmg artifact"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-macOS.dmg"
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Release artifacts created:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
