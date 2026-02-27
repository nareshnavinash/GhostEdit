#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/GhostEdit.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedDataTests"
TEST_RESULTS_DIR="$ROOT_DIR/build/test-results"
XCODEBUILD_LOG_PATH="$TEST_RESULTS_DIR/xcodebuild-build-for-testing.log"
PROFDATA_PATH="$TEST_RESULTS_DIR/GhostEditTests.profdata"
COVERAGE_REPORT_PATH="$TEST_RESULTS_DIR/coverage-report.txt"
TEST_BUNDLE_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/GhostEditTests.xctest"
TEST_BINARY_PATH="$TEST_BUNDLE_PATH/Contents/MacOS/GhostEditTests"
CORE_BINARY_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/GhostEditCore.framework/Versions/A/GhostEditCore"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required to generate GhostEdit.xcodeproj" >&2
    exit 1
  fi
  (cd "$ROOT_DIR" && xcodegen generate --spec project.yml >/dev/null)
fi

mkdir -p "$TEST_RESULTS_DIR"
find "$TEST_RESULTS_DIR" -name "GhostEditTests-*.profraw" -delete
rm -f "$PROFDATA_PATH" "$COVERAGE_REPORT_PATH"

echo "[1/3] Building tests (build-for-testing)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme GhostEditTests \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -enableCodeCoverage YES \
  build-for-testing 2>&1 | tee "$XCODEBUILD_LOG_PATH"

echo "[2/3] Running unit tests..."
LLVM_PROFILE_FILE="$TEST_RESULTS_DIR/GhostEditTests-%p.profraw" \
  xcrun xctest "$TEST_BUNDLE_PATH"

echo "[3/3] Validating 100% line coverage for guarded files..."
PROFILE_FILES=()
while IFS= read -r profile_file; do
  PROFILE_FILES+=("$profile_file")
done < <(find "$TEST_RESULTS_DIR" -name "GhostEditTests-*.profraw" -type f | sort)
if [[ ${#PROFILE_FILES[@]} -eq 0 ]]; then
  echo "No profile data files were produced by xctest." >&2
  exit 1
fi

xcrun llvm-profdata merge -sparse "${PROFILE_FILES[@]}" -o "$PROFDATA_PATH"

REQUIRED_FILES=(
  "$ROOT_DIR/GhostEdit/Sources/ConfigManager.swift"
  "$ROOT_DIR/GhostEdit/Sources/ShellRunner.swift"
  "$ROOT_DIR/GhostEdit/Sources/ClaudeRuntimeSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/CorrectionHistoryStore.swift"
  "$ROOT_DIR/GhostEdit/Sources/HistoryTableModel.swift"
  "$ROOT_DIR/GhostEdit/Sources/HistoryCSVExporter.swift"
  "$ROOT_DIR/GhostEdit/Sources/HotkeySupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/WritingCoachSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/AccessibilitySupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/AccessibilityTextSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/SettingsLayoutSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/TokenPreservationSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/MenuBarIconSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/WritingCoachLayoutSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/HUDOverlaySupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/DeveloperModeSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/DiffSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/SettingsExportSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/CorrectionStatisticsSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/TooltipSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/FallbackSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/TokenEstimationSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/PartialCorrectionSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/AppProfileSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/UpdateCheckSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/StreamingPreviewSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/SpellCheckSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/LiveFeedbackSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/LocalModelSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/PythonEnvironmentSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/HardwareCompatibilitySupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/LocalFixSupport.swift"
  "$ROOT_DIR/GhostEdit/Sources/StatusDisplaySupport.swift"
)

xcrun llvm-cov report \
  -instr-profile="$PROFDATA_PATH" \
  "$TEST_BINARY_PATH" \
  -object "$CORE_BINARY_PATH" \
  "${REQUIRED_FILES[@]}" | tee "$COVERAGE_REPORT_PATH"

/usr/bin/python3 - "$COVERAGE_REPORT_PATH" "${REQUIRED_FILES[@]}" <<'PY'
import pathlib
import sys

coverage_report_path = pathlib.Path(sys.argv[1])
required_files = [pathlib.Path(p).name for p in sys.argv[2:]]

rows = {}
for raw_line in coverage_report_path.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("-") or line.startswith("Filename"):
        continue

    columns = line.split()
    if len(columns) < 10:
        continue

    if not columns[1].isdigit():
        continue

    file_name = pathlib.Path(columns[0]).name
    line_cover = columns[9]
    if not line_cover.endswith("%"):
        continue

    rows[file_name] = float(line_cover.rstrip("%"))

failed = False
for file_name in required_files:
    if file_name not in rows:
        print(f"Missing coverage row for {file_name}", file=sys.stderr)
        failed = True
        continue

    pct = rows[file_name]
    print(f"{file_name}: {pct:.2f}%")
    if pct < 100.0:
        print(f"Coverage gate failed for {file_name}: expected 100.00%, got {pct:.2f}%", file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)
PY

echo "Coverage gate passed."
