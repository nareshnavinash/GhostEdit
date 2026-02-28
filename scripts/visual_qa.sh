#!/usr/bin/env bash
# visual_qa.sh — Semi-automated screenshot capture for GhostEdit visual QA.
# Takes screenshots of GhostEdit windows and saves them to build/visual-qa/.
# Compare against golden screenshots to detect visual regressions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/visual-qa"
GOLDEN_DIR="$ROOT_DIR/build/visual-qa-golden"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="$OUTPUT_DIR/$TIMESTAMP"

mkdir -p "$RUN_DIR"

echo "=== GhostEdit Visual QA ==="
echo "Output: $RUN_DIR"
echo ""

# Check that GhostEdit is running
if ! pgrep -x "GhostEdit" > /dev/null 2>&1; then
    echo "ERROR: GhostEdit is not running. Launch it first:"
    echo "  open /Applications/GhostEdit.app"
    exit 1
fi

GHOSTEDIT_PID=$(pgrep -x "GhostEdit")
echo "Found GhostEdit (PID: $GHOSTEDIT_PID)"

# Helper: capture a screenshot of a specific window by title substring
capture_window() {
    local name="$1"
    local filename="$2"
    local window_id

    window_id=$(osascript -e "
        tell application \"System Events\"
            tell process \"GhostEdit\"
                set windowList to every window
                repeat with w in windowList
                    if name of w contains \"$name\" then
                        return id of w
                    end if
                end repeat
            end tell
        end tell
        return missing value
    " 2>/dev/null || echo "")

    if [ -n "$window_id" ] && [ "$window_id" != "missing value" ]; then
        screencapture -l "$window_id" "$RUN_DIR/$filename"
        echo "  Captured: $filename (window ID $window_id)"
    else
        echo "  SKIPPED: $filename (window '$name' not found)"
    fi
}

# Capture menu bar icon area
echo ""
echo "1. Menu bar screenshot..."
screencapture -R "0,0,400,25" "$RUN_DIR/01_menubar.png" 2>/dev/null && echo "  Captured: 01_menubar.png" || echo "  SKIPPED: 01_menubar.png"

# Open menu and capture
echo ""
echo "2. Opening Settings window..."
osascript -e 'tell application "GhostEdit" to activate' 2>/dev/null
sleep 1

echo ""
echo "3. Capturing Settings window..."
capture_window "Settings" "03_settings.png"

echo ""
echo "4. Capturing History window..."
capture_window "History" "04_history.png"

echo ""
echo "5. Capturing any HUD overlay..."
capture_window "GhostEdit" "05_hud.png"

echo ""
echo "6. Capturing Streaming Preview..."
capture_window "Preview" "06_streaming_preview.png"

echo ""
echo "7. Capturing Diff Preview..."
capture_window "Diff" "07_diff_preview.png"

echo ""
echo "8. Capturing Developer Console..."
capture_window "Console" "08_dev_console.png"

echo ""
echo "9. Full screen capture..."
screencapture "$RUN_DIR/09_fullscreen.png"
echo "  Captured: 09_fullscreen.png"

# Compare against golden if available
echo ""
if [ -d "$GOLDEN_DIR" ]; then
    echo "=== Comparing against golden screenshots ==="
    DIFF_COUNT=0
    for golden_file in "$GOLDEN_DIR"/*.png; do
        basename=$(basename "$golden_file")
        run_file="$RUN_DIR/$basename"
        if [ -f "$run_file" ]; then
            # Use sips to get dimensions and basic comparison
            golden_size=$(sips -g pixelHeight -g pixelWidth "$golden_file" 2>/dev/null | grep pixel | awk '{print $2}' | tr '\n' 'x')
            run_size=$(sips -g pixelHeight -g pixelWidth "$run_file" 2>/dev/null | grep pixel | awk '{print $2}' | tr '\n' 'x')
            if [ "$golden_size" != "$run_size" ]; then
                echo "  DIFF: $basename — size changed ($golden_size -> $run_size)"
                DIFF_COUNT=$((DIFF_COUNT + 1))
            else
                echo "  OK:   $basename"
            fi
        else
            echo "  MISSING: $basename (not captured this run)"
            DIFF_COUNT=$((DIFF_COUNT + 1))
        fi
    done
    if [ "$DIFF_COUNT" -eq 0 ]; then
        echo "All golden screenshots match."
    else
        echo "$DIFF_COUNT difference(s) found. Review screenshots in $RUN_DIR"
    fi
else
    echo "No golden screenshots found. To set a baseline:"
    echo "  mkdir -p $GOLDEN_DIR"
    echo "  cp $RUN_DIR/*.png $GOLDEN_DIR/"
fi

echo ""
echo "=== Done ==="
echo "Screenshots saved to: $RUN_DIR"
echo ""
echo "Next steps:"
echo "  1. Review screenshots visually"
echo "  2. Walk through docs/VISUAL_QA.md checklist"
echo "  3. To set golden baseline: cp $RUN_DIR/*.png $GOLDEN_DIR/"
