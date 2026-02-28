# GhostEdit — Project Guide

## What is GhostEdit?
A macOS menu bar app (AppKit, no SwiftUI/XIBs) that fixes grammar/spelling in any text field system-wide. User presses a hotkey, selected text is sent to an LLM (Claude/Gemini/Codex), corrected text is pasted back. Supports streaming preview, diff view, writing coach, and history.

**Repo:** https://github.com/nareshnavinash/GhostEdit.git
**Version:** 7.7.0 (build 37) | **macOS 13.0+** | **Swift 5**

## Architecture

### Three Targets (project.yml / GhostEdit.xcodeproj)
- **GhostEditCore** — Framework. All source files EXCEPT main.swift. This is what tests import.
- **GhostEdit** — App. Only main.swift + assets. Links GhostEditCore.
- **GhostEditTests** — Unit tests. Tests GhostEditCore.

### Source Files (49 files, ~14K lines in `GhostEdit/Sources/`)

#### AppDelegate (~2,600 lines) — Orchestration & UI
Contains the `AppDelegate` class and `extension AppDelegate: DeveloperModeLogger`. Organized with MARK sections:

| MARK Section | Line | What It Does |
|---|---|---|
| Properties | 8 | All stored properties (windows, controllers, state) |
| App Lifecycle | 66 | `applicationDidFinishLaunching`, setup, teardown |
| Menu Bar Setup | 116 | Status item, menus, NSMenu construction |
| Menu Actions | 399 | Menu item handlers (settings, history, quit, etc.) |
| Hotkey Registration | 463 | Carbon hotkey registration/deregistration |
| Local Fix Pipeline (cmd+E) | 713 | `handleHotkeyTrigger()` → copy → process → paste pipeline |
| Cloud Fix Pipeline (cmd+shift+E) | 1159 | Cloud LLM correction flow |
| Streaming | 1582 | Streaming preview coordination |
| Text Application & Write-back | 1694 | Paste corrected text via AX or clipboard |
| HUD Management | 1815 | Show/hide/update HUD overlay |
| Processing State | 1853 | Processing flag management |
| Accessibility & Alerts | 1864 | Permission checks, alert dialogs |
| Sound & Notifications | 1937 | Audio feedback, user notifications |
| Status Bar | 1980 | Menu bar status text & color dot (delegates to `StatusDisplaySupport`) |
| Window Presentation | 2035 | Present settings, history, diff, streaming windows |
| Settings Import/Export | 2104 | Settings file import/export via NSSavePanel |
| Update Check | 2164 | GitHub release update checking |
| Writing Coach | 2241 | Writing coach panel management |
| History | 2495 | History recording helpers |
| Clipboard | 2505 | Clipboard utilities |
| Developer Mode | 2528 | Developer console, logging |

#### 7 Controller Files (extracted from AppDelegate)
Each is a standalone `final class` communicating via closures/references passed at init.

| File | Lines | Class | Purpose |
|---|---|---|---|
| `DeveloperConsoleController.swift` | 133 | `DeveloperConsoleController` | Log viewer with text view, clear/copy buttons |
| `DiffPreviewController.swift` | 151 | `DiffPreviewController` | Side-by-side diff with apply/cancel |
| `StreamingPreviewController.swift` | 592 | `StreamingPreviewController` | Live streaming + char-level diff + change navigation. Also contains `FlippedClipView` (internal) and `LineNumberRulerView` (private) |
| `SettingsWindowController.swift` | 2,275 | `SettingsWindowController` | Tabbed settings: General / Hotkey / Behavior / Advanced. `NSToolbarDelegate` |
| `HistoryWindowController.swift` | 605 | `HistoryWindowController` | Table with search, filter, badges. Contains `HistoryCopyTableView` (private) |
| `HUDOverlayController.swift` | 585 | `HUDOverlayController` | Ghost overlay with animations. Contains `CGPath` extension (private) |
| `LiveFeedbackController.swift` | 1,414 | `LiveFeedbackController` | Real-time spell/grammar feedback panel. `requestAutoApply()` for cmd+E post-fix cleanup. Contains `IssueRowView` (private) |

#### Infrastructure (non-UI services)

| File | Lines | Purpose |
|---|---|---|
| `ShellRunner.swift` | 715 | Runs CLI tools, `correctTextPreservingTokens()`, `correctTextStreaming()` |
| `ConfigManager.swift` | 537 | Reads/writes `~/.ghostedit/config.json`, `AppConfig` struct |
| `PersistentCLISession.swift` | 542 | Long-lived CLI process for streaming |
| `PersistentShellSession.swift` | 214 | Shell session management |
| `LocalModelRunner.swift` | 343 | Local ML model inference |
| `HotkeyManager.swift` | 228 | Carbon hotkey registration |
| `ClipboardManager.swift` | 169 | NSPasteboard read/write |
| `CorrectionHistoryStore.swift` | 94 | Persists `history.json` |
| `HistoryTableModel.swift` | 59 | Filtering/sorting for history table |
| `HistoryCSVExporter.swift` | 53 | Export history to CSV |
| `HarperBridge.swift` | 61 | FFI bridge to Harper spell-checker |
| `LaunchAtLoginManager.swift` | 27 | Launch-at-login toggle |

#### Pure-Logic Support Modules (enum namespaces, no AppKit, 100% tested)

| File | Lines | Key Methods |
|---|---|---|
| `TokenPreservationSupport.swift` | 286 | `preserveTokens()`, `restoreTokens()` — protect URLs, emails, code blocks from LLM changes |
| `WritingCoachSupport.swift` | 244 | `analyzeWriting()`, `formatFeedback()` — writing quality analysis |
| `DiffSupport.swift` | 225 | `wordDiff()` for summaries/counts, `charDiff()` for display highlighting |
| `AccessibilityTextSupport.swift` | 212 | AX text extraction helpers |
| `SpellCheckSupport.swift` | 188 | `SpellCheckIssue` struct, NSSpellChecker integration |
| `LocalModelSupport.swift` | 155 | Local model configuration and validation. Single recommended model: `vennify/t5-base-grammar-correction` |
| `ClaudeRuntimeSupport.swift` | 143 | Claude API formatting |
| `HUDOverlaySupport.swift` | 133 | HUD layout calculations |
| `HotkeySupport.swift` | 119 | Hotkey string parsing/formatting |
| `CorrectionStatisticsSupport.swift` | 108 | Stats computation from history |
| `LiveFeedbackSupport.swift` | 103 | Issue filtering, dedup for live feedback |
| `PythonEnvironmentSupport.swift` | 92 | Python env detection for local models |
| `HardwareCompatibilitySupport.swift` | 85 | Hardware capability checks |
| `DeveloperModeSupport.swift` | 67 | Dev mode state/log formatting |
| `MenuBarIconSupport.swift` | 59 | Menu bar icon rendering |
| `StreamingPreviewSupport.swift` | 58 | Streaming text processing |
| `AppProfileSupport.swift` | 58 | Per-app profile matching |
| `TooltipSupport.swift` | 57 | Tooltip text generation |
| `PartialCorrectionSupport.swift` | 55 | Partial text correction logic |
| `TokenEstimationSupport.swift` | 54 | Token count estimation |
| `UpdateCheckSupport.swift` | 50 | GitHub release version comparison |
| `SettingsExportSupport.swift` | 48 | Settings serialization |
| `LocalFixSupport.swift` | 37 | `extractLineAtCursor()`, `mergeIssues()` — local fix pipeline helpers |
| `FallbackSupport.swift` | 37 | Fallback provider logic |
| `WritingCoachLayoutSupport.swift` | 31 | Writing coach panel layout |
| `StatusDisplaySupport.swift` | 22 | `statusColor(for:)` → `.green`/`.orange`/`.red` based on status text |
| `SettingsLayoutSupport.swift` | 16 | Settings panel layout constants |
| `AccessibilitySupport.swift` | 11 | AX permission check |

### Key Correction Flow

**Local Fix (cmd+E):**
1. `handleLocalFixHotkey()` → copy selection → `applyRuleBasedTextFixes()` (iterative, up to 3 passes of Harper + NSSpellChecker)
2. If local model configured: send spell-fixed text to model → `applyRuleBasedTextFixes()` on model output (post-model polish)
3. Write corrected text back via AX → `liveFeedbackController.requestAutoApply()` (auto-applies any remaining grammar fixes LiveFeedback detects on next scan)

**Cloud Fix (cmd+shift+E):**
1. `handleHotkeyTrigger()` → `attemptCopySelection()` → `waitForCopiedText()` → `processSelectedText()`
2. Non-streaming: `shellRunner.correctTextPreservingTokens()` → `recordHistoryEntry(succeeded: true)` → paste via AX or clipboard
3. Streaming: `shellRunner.correctTextStreaming()` → `StreamingPreviewController.markComplete()` → user accepts/cancels

**Token Protection:** Issues overlapping protected tokens (@mentions, URLs, etc.) are filtered, but fixes that preserve the token text and only add punctuation (e.g., `@Chema → @Chema,`) are allowed through.

**LiveFeedback Auto-Apply:** After cmd+E writes text back, `requestAutoApply()` clears LiveFeedback's scan cache and sets a flag. On the next polling cycle, LiveFeedback re-checks the text, and if fixable issues remain, auto-applies them via `applyAllFixes()`.

### Key Types
- `AppConfig` (in ConfigManager.swift) — all user settings
- `CorrectionHistoryEntry` with `succeeded: Bool` — history records
- `SpellCheckIssue(word:range:kind:suggestions:)` — spell check results
- `DiffSegment` — diff display units
- HUD states: `.working`, `.success`, `.successWithCount(Int)`, `.error(String)`
- `FlippedClipView` (in StreamingPreviewController.swift) — used by both StreamingPreviewController and SettingsWindowController (internal access)

## Build & Test

```bash
# Build release
xcodebuild build -project GhostEdit.xcodeproj -scheme GhostEdit -configuration Release

# Run tests (989+ tests)
xcodebuild test -project GhostEdit.xcodeproj -scheme GhostEditTests -destination 'platform=macOS'

# Full coverage check (what pre-commit/pre-push hooks run)
./scripts/run_tests_with_coverage.sh
```

## Coverage Gate (CRITICAL)
Pre-commit and pre-push hooks (`.githooks/`) run `scripts/run_tests_with_coverage.sh` which enforces **100% line coverage** on **33 guarded files**. If you add/modify code in any guarded file, you MUST add tests. The guarded files are all Support modules + ConfigManager + ShellRunner + CorrectionHistoryStore + HistoryTableModel + HistoryCSVExporter.

**NOT guarded** (no coverage needed): AppDelegate.swift, the 7 controller files (DeveloperConsoleController, DiffPreviewController, StreamingPreviewController, SettingsWindowController, HistoryWindowController, HUDOverlayController, LiveFeedbackController), ClipboardManager.swift, HotkeyManager.swift, LaunchAtLoginManager.swift, PersistentCLISession.swift, PersistentShellSession.swift, LocalModelRunner.swift, HarperBridge.swift, main.swift.

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
# 1. Bump version in project.yml (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
# 2. Regenerate: xcodegen generate --spec project.yml
# 3. Build, test, commit, push (hooks run tests)
# 4. Publish release + update Homebrew tap (builds, tags, uploads DMG/ZIP, updates cask):
./scripts/publish_release.sh
```

### Homebrew Tap
The `homebrew-ghostedit/` directory is a clone of `nareshnavinash/homebrew-ghostedit` (gitignored).
`publish_release.sh` auto-updates `Casks/ghostedit.rb` with the new version and sha256, then pushes.
Users install via: `brew tap nareshnavinash/ghostedit && brew install --cask ghostedit`

## Key Config
- Config dir: `~/.ghostedit/` (migrated from `~/.grammarfixer/`)
- Files: `config.json`, `prompt.txt`, `history.json`, `profiles.json`
- Providers: Claude (.claude), Gemini (.gemini), Codex (.codex)

## SourceKit Warnings
Cross-module SourceKit errors like "Cannot find 'AppConfig' in scope" are **false positives** — they happen because SourceKit can't resolve types across the Core framework boundary. If `xcodebuild build` succeeds, ignore them.

## Conventions
- All UI is programmatic AppKit (NSWindow, NSView, NSTableView, etc.)
- Support modules are `enum` namespaces with `static` methods (no instances)
- Controllers are `final class` at file top level, communicate via closures (no direct AppDelegate property access)
- History entries: `CorrectionHistoryEntry` with `succeeded: Bool`
- Status badge uses `filteredEntries[row].succeeded` boolean directly (not string matching)
- HUD states: `.working`, `.success`, `.successWithCount(Int)`, `.error(String)`
- Diff: `DiffSupport.wordDiff()` for summaries/counts, `DiffSupport.charDiff()` for display highlighting
- Version bumps go in `project.yml`, then regenerate with `xcodegen generate --spec project.yml`
