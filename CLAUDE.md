# GhostEdit — Project Guide

## What is GhostEdit?
A macOS menu bar app (AppKit, no SwiftUI/XIBs) that fixes grammar/spelling in any text field system-wide. User presses a hotkey, selected text is sent to an LLM (Claude/Gemini/Codex), corrected text is pasted back. Supports streaming preview, diff view, writing coach, and history.

**Repo:** https://github.com/nareshnavinash/GhostEdit.git
**Version:** 6.0.0 (build 26) | **macOS 13.0+** | **Swift 5**

## Architecture

### Three Targets (project.yml / GhostEdit.xcodeproj)
- **GhostEditCore** — Framework. All source files EXCEPT main.swift. This is what tests import.
- **GhostEdit** — App. Only main.swift + assets. Links GhostEditCore.
- **GhostEditTests** — Unit tests. Tests GhostEditCore.

### Source Files (33 files, ~9K lines in `GhostEdit/Sources/`)
The main file is **AppDelegate.swift** (~4,600 lines) containing:
- `AppDelegate` (lines 6-1856) — Menu bar, hotkey handling, text processing pipeline
- `DeveloperConsoleController` (1871-2001) — Log viewer
- `DiffPreviewController` (2003-2151) — Side-by-side diff
- `StreamingPreviewController` (2153-2647) — Live streaming + char-level diff + change nav
- `LineNumberRulerView` (2651-2736) — Gutter line numbers
- `SettingsWindowController` (2738-3636) — Tabbed settings (General/Hotkey/Behavior/Advanced)
- `HistoryWindowController` (3638-4219) — Table with search, filter, badges
- `HUDOverlayController` (4242-4556) — Ghost overlay with animations

All other files are **pure-logic Support modules** (no AppKit imports) that are 100% testable.

### Key Correction Flow
1. `handleHotkeyTrigger()` → `attemptCopySelection()` → `waitForCopiedText()` → `processSelectedText()`
2. Non-streaming: `shellRunner.correctTextPreservingTokens()` → `recordHistoryEntry(succeeded: true)` → paste via AX or clipboard
3. Streaming: `shellRunner.correctTextStreaming()` → `StreamingPreviewController.markComplete()` → user accepts/cancels

## Build & Test

```bash
# Build release
xcodebuild build -project GhostEdit.xcodeproj -scheme GhostEdit -configuration Release

# Run tests (432+ tests)
xcodebuild test -project GhostEdit.xcodeproj -scheme GhostEditTests -destination 'platform=macOS'

# Full coverage check (what pre-commit/pre-push hooks run)
./scripts/run_tests_with_coverage.sh
```

## Coverage Gate (CRITICAL)
Pre-commit and pre-push hooks (`.githooks/`) run `scripts/run_tests_with_coverage.sh` which enforces **100% line coverage** on 26 guarded files. If you add/modify code in any guarded file, you MUST add tests. The 26 guarded files are all Support modules + ConfigManager + ShellRunner + CorrectionHistoryStore + HistoryTableModel + HistoryCSVExporter.

**NOT guarded** (no coverage needed): AppDelegate.swift, ClipboardManager.swift, HotkeyManager.swift, LaunchAtLoginManager.swift, PersistentCLISession.swift, PersistentShellSession.swift, main.swift.

## Install Flow
```bash
# Quit running app
osascript -e 'tell application "GhostEdit" to quit' 2>/dev/null; sleep 1
# Replace and re-sign
rm -rf /Applications/GhostEdit.app
cp -R "$(xcodebuild build -project GhostEdit.xcodeproj -scheme GhostEdit -configuration Release -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $NF}')/GhostEdit.app" /Applications/GhostEdit.app
codesign --force --deep --sign - /Applications/GhostEdit.app
open /Applications/GhostEdit.app
```

## Release Flow
```bash
# Bump version in project.pbxproj (MARKETING_VERSION + CURRENT_PROJECT_VERSION, 2 occurrences each)
# Build, test, commit, push (hooks run tests), then:
gh release create vX.Y.Z-beta.N --prerelease --title "..." --notes "..."
```

## Key Config
- Config dir: `~/.ghostedit/` (migrated from `~/.grammarfixer/`)
- Files: `config.json`, `prompt.txt`, `history.json`, `profiles.json`
- Providers: Claude (.claude), Gemini (.gemini), Codex (.codex)

## SourceKit Warnings
Cross-module SourceKit errors like "Cannot find 'AppConfig' in scope" are **false positives** — they happen because SourceKit can't resolve types across the Core framework boundary. If `xcodebuild build` succeeds, ignore them.

## Conventions
- All UI is programmatic AppKit (NSWindow, NSView, NSTableView, etc.)
- Support modules are `enum` namespaces with `static` methods (no instances)
- History entries: `CorrectionHistoryEntry` with `succeeded: Bool`
- Status badge uses `filteredEntries[row].succeeded` boolean directly (not string matching)
- HUD states: `.working`, `.success`, `.successWithCount(Int)`, `.error(String)`
- Diff: `DiffSupport.wordDiff()` for summaries/counts, `DiffSupport.charDiff()` for display highlighting
