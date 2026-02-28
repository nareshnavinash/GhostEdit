#!/usr/bin/env bash
# publish_release.sh — Build, tag, upload artifacts, and update the Homebrew cask.
#
# Usage:
#   ./scripts/publish_release.sh          # reads version from project.yml
#   ./scripts/publish_release.sh 7.6.0    # override version
#
# What it does:
#   1. Reads the version from project.yml (or uses the argument)
#   2. Builds release artifacts (zip + dmg) via build_release.sh
#   3. Creates a GitHub release (or uses existing) and uploads artifacts
#   4. Updates homebrew-ghostedit/Casks/ghostedit.rb with the new version + sha256
#   5. Commits and pushes the Homebrew tap
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/build/release"
TAP_DIR="$ROOT_DIR/homebrew-ghostedit"
CASK_FILE="$TAP_DIR/Casks/ghostedit.rb"
REPO="nareshnavinash/GhostEdit"

# ---------------------------------------------------------------------------
# 1. Determine version
# ---------------------------------------------------------------------------
if [[ -n "${1:-}" ]]; then
  VERSION="$1"
else
  VERSION=$(grep 'MARKETING_VERSION:' "$ROOT_DIR/project.yml" | head -1 | awk '{print $2}')
fi

if [[ -z "$VERSION" ]]; then
  echo "Error: could not determine version. Pass it as an argument or set MARKETING_VERSION in project.yml." >&2
  exit 1
fi

TAG="v$VERSION"
echo "Publishing GhostEdit $TAG"
echo "==========================================="

# ---------------------------------------------------------------------------
# 2. Build release artifacts
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Building release artifacts..."
"$ROOT_DIR/scripts/build_release.sh"

DMG_PATH="$RELEASE_DIR/GhostEdit-macOS.dmg"
ZIP_PATH="$RELEASE_DIR/GhostEdit-macOS.zip"

if [[ ! -f "$DMG_PATH" ]] || [[ ! -f "$ZIP_PATH" ]]; then
  echo "Error: release artifacts not found in $RELEASE_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Create GitHub release and upload artifacts
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Creating GitHub release $TAG..."

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "  Release $TAG already exists — uploading artifacts (overwriting if present)..."
  gh release upload "$TAG" "$DMG_PATH" "$ZIP_PATH" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$DMG_PATH" "$ZIP_PATH" \
    --repo "$REPO" \
    --title "$TAG" \
    --notes "GhostEdit $VERSION" \
    --latest
fi

echo "  Release: https://github.com/$REPO/releases/tag/$TAG"

# ---------------------------------------------------------------------------
# 4. Update Homebrew cask
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Updating Homebrew cask formula..."

if [[ ! -d "$TAP_DIR/.git" ]]; then
  echo "  Cloning homebrew-ghostedit tap..."
  git clone "https://github.com/nareshnavinash/homebrew-ghostedit.git" "$TAP_DIR"
fi

# Pull latest to avoid conflicts
git -C "$TAP_DIR" pull --rebase --quiet 2>/dev/null || true

DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "  Version: $VERSION"
echo "  SHA256:  $DMG_SHA256"

# Update version and sha256 in the cask file
sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"$DMG_SHA256\"/" "$CASK_FILE"

echo "  Updated $CASK_FILE"

# ---------------------------------------------------------------------------
# 5. Commit and push the tap
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Pushing Homebrew tap update..."

cd "$TAP_DIR"
git add Casks/ghostedit.rb
if git diff --cached --quiet; then
  echo "  No changes to commit (cask already up to date)"
else
  git commit -m "Update GhostEdit to $VERSION"
  git push
  echo "  Pushed to homebrew-ghostedit"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "[5/5] Done!"
echo "==========================================="
echo "  Release:  https://github.com/$REPO/releases/tag/$TAG"
echo "  Homebrew: brew tap nareshnavinash/ghostedit && brew install --cask ghostedit"
echo ""
echo "Users can now install or upgrade with:"
echo "  brew upgrade --cask ghostedit"
