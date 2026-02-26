# Codebase Structure

**Analysis Date:** 2026-02-26

## Directory Layout

```
GrammarFixer/
├── GhostEdit/
│   ├── Sources/                    # 33 Swift source files (9K+ lines)
│   │   ├── AppDelegate.swift       # ~4,600 lines: Main orchestrator + 7 window controllers
│   │   ├── main.swift              # Entry point (1 file in GhostEdit target, rest in Core)
│   │   ├── ClipboardManager.swift  # Clipboard read/write, CGEvent simulation
│   │   ├── HotkeyManager.swift     # Carbon hotkey registration
│   │   ├── ConfigManager.swift     # Config file I/O, validation
│   │   ├── ShellRunner.swift       # CLI execution, streaming/non-streaming
│   │   ├── PersistentCLISession.swift  # Keep-alive process for CLI
│   │   ├── PersistentShellSession.swift # Low-level shell communication
│   │   ├── CorrectionHistoryStore.swift # History JSON persistence
│   │   ├── *Support.swift          # 23 pure-logic Support modules
│   │   └── HarperBridge.swift      # On-device spell check binding
│   ├── Assets.xcassets/            # App icon, menu bar icons
│   └── Info.plist                  # App metadata
├── GhostEditTests/                 # 28 test files, 432+ test cases
│   └── *Tests.swift                # Unit tests for Support modules + managers
├── GhostEdit.xcodeproj/            # Xcode project (3 targets)
│   └── project.pbxproj             # Build configuration
├── project.yml                      # XcodeGen YAML (generates pbxproj)
├── CLAUDE.md                        # Project guide (this repo)
├── README.md                        # User-facing documentation
├── scripts/                         # Build/test helpers
│   └── run_tests_with_coverage.sh   # Coverage gate (100% on 26 guarded files)
├── .githooks/                       # Pre-commit/pre-push hooks (run coverage)
└── build/                           # Xcode build artifacts (untracked)
```

## Directory Purposes

**GhostEdit/Sources/:**
- **Purpose:** All Swift source code for the app
- **Contains:** AppDelegate (UI orchestration), 23 Support enums (pure logic), 7 Manager/Controller classes
- **Key files:**
  - `AppDelegate.swift` — Monolithic orchestrator (menu bar, hotkey, processing pipeline)
  - `ConfigManager.swift` — Load/save ~/.ghostedit/config.json
  - `ShellRunner.swift` — Execute external CLI
  - `*Support.swift` — Reusable, testable algorithms (no AppKit)

**GhostEdit/Assets.xcassets/:**
- **Purpose:** App icon and menu bar icons (idle/processing states)
- **Contains:** AppIcon.appiconset, MenuBarIconIdle.imageset, MenuBarIconProcessing.imageset

**GhostEditTests/:**
- **Purpose:** Unit tests for all logic modules
- **Contains:** 28 test files, one per Support module + ConfigManager, ShellRunner, etc.
- **Coverage:** 100% line coverage required on 26 guarded files (all except AppDelegate.swift, ClipboardManager.swift, HotkeyManager.swift, LaunchAtLoginManager.swift, PersistentCLISession.swift, PersistentShellSession.swift, main.swift)

**GhostEdit.xcodeproj/:**
- **Purpose:** Xcode build project
- **Contains:** 3 targets (GhostEditCore framework, GhostEdit app, GhostEditTests)
- **Generated from:** project.yml (XcodeGen)

## Key File Locations

**Entry Points:**
- `GhostEdit/Sources/main.swift` — Creates NSApplication, sets AppDelegate, runs app
- `GhostEdit/Sources/AppDelegate.swift` (lines 54-81) — applicationDidFinishLaunching: bootstraps config, registers hotkey, starts live feedback

**Configuration:**
- `~/.ghostedit/config.json` — User config (provider, model, timeout, hotkey, language, etc.)
- `~/.ghostedit/prompt.txt` — System prompt for text correction
- `~/.ghostedit/history.json` — JSON array of CorrectionHistoryEntry
- `~/.ghostedit/profiles.json` — Per-app overrides (bundleIdentifier → custom model/prompt)
- `GhostEdit/Sources/ConfigManager.swift` — Manages all config files

**Core Logic:**
- `GhostEdit/Sources/AppDelegate.swift` (lines 879-926) — handleHotkeyTrigger: entry point for user action
- `GhostEdit/Sources/AppDelegate.swift` (lines 941-1012) — attemptCopySelection, waitForCopiedText: clipboard read
- `GhostEdit/Sources/AppDelegate.swift` (lines 1015-1100) — processSelectedText: load config, invoke ShellRunner
- `GhostEdit/Sources/ShellRunner.swift` — correctTextPreservingTokens(), correctTextStreaming(): CLI execution
- `GhostEdit/Sources/TokenPreservationSupport.swift` — protectTokens(), restoreTokens(): preserve URLs, emails, code, emojis

**Testing:**
- `GhostEditTests/*.swift` — Unit tests, one per module
- `scripts/run_tests_with_coverage.sh` — Coverage gate script (invoked by .githooks/)

**Assets:**
- `GhostEdit/Assets.xcassets/AppIcon.appiconset/` — App icon
- `GhostEdit/Assets.xcassets/MenuBarIconIdle.imageset/` — Menu bar icon (idle state)
- `GhostEdit/Assets.xcassets/MenuBarIconProcessing.imageset/` — Menu bar icon (processing state)

## Naming Conventions

**Files:**
- `AppDelegate.swift` — Main orchestrator (single file, ~4,600 lines, contains 8 classes)
- `*Manager.swift` — Managers: ConfigManager, HotkeyManager, ClipboardManager, LaunchAtLoginManager
- `*Support.swift` — Pure-logic Support enums: TokenPreservationSupport, DiffSupport, etc. (23 total)
- `Persistent*Session.swift` — Process/session managers: PersistentCLISession, PersistentShellSession
- `*Controller.swift` — Inside AppDelegate: DeveloperConsoleController, SettingsWindowController, etc.
- `*Tests.swift` — Unit tests: ConfigManagerTests, TokenPreservationSupportTests, etc.

**Directories:**
- `GhostEdit/Sources/` — All Swift source code
- `GhostEdit/Assets.xcassets/` — App/icon assets
- `GhostEditTests/` — Test files (parallel to Sources/)
- `.githooks/` — Git hooks (pre-commit, pre-push)
- `scripts/` — Build/test scripts

**Enums/Classes:**
- Support modules: `enum TokenPreservationSupport`, `enum DiffSupport`, etc.
- Managers: `final class ConfigManager`, `final class ShellRunner`
- Controllers: `final class SettingsWindowController`, `final class HistoryWindowController`
- Models: `struct CorrectionHistoryEntry`, `enum CLIProvider`

## Where to Add New Code

**New Feature:**
1. **Core Logic:** Add to new file `GhostEdit/Sources/FeatureSupport.swift` as `enum FeatureSupport { static func ... }`
2. **Tests:** Create `GhostEditTests/FeatureSupportTests.swift` with 100% coverage
3. **Integration:** Call from `AppDelegate.swift` in appropriate method (e.g., `processSelectedText` or `handleHotkeyTrigger`)

**New Window/Controller:**
1. Add class inside `GhostEdit/Sources/AppDelegate.swift` (e.g., `final class FeatureWindowController: NSWindowController`)
2. Instantiate in `AppDelegate` with lazy property
3. Add menu item in `configureStatusItem()` to open window

**New Manager/Utility:**
1. Create new file `GhostEdit/Sources/FeatureManager.swift` with `final class FeatureManager`
2. Add unit tests `GhostEditTests/FeatureManagerTests.swift` (must reach 100% coverage if file is "guarded")
3. Wire into AppDelegate as property/lazy property

**Configuration Option:**
1. Add field to `AppConfig` struct in `ConfigManager.swift` (e.g., `var newOption: Bool`)
2. Add UI control in `SettingsWindowController` (in AppDelegate.swift, lines 3041+)
3. Update `~/.ghostedit/config.json` schema + README

**New Support Algorithm:**
1. Create `GhostEdit/Sources/NewAlgorithmSupport.swift` as pure-logic enum
2. No AppKit imports — pure Foundation
3. Add comprehensive unit tests `GhostEditTests/NewAlgorithmSupportTests.swift`
4. Call from AppDelegate or other Support modules

## Special Directories

**build/:**
- **Purpose:** Xcode build artifacts (derived data)
- **Generated:** Yes (run `xcodebuild build`)
- **Committed:** No (in .gitignore)

**GhostEdit.xcodeproj/xcshareddata/:**
- **Purpose:** Shared Xcode schemes (GhostEdit, GhostEditTests)
- **Generated:** No (committed)
- **Committed:** Yes

**.githooks/:**
- **Purpose:** Pre-commit/pre-push hooks that run `scripts/run_tests_with_coverage.sh`
- **Generated:** No (committed)
- **Committed:** Yes

**scripts/:**
- **Purpose:** Build, test, coverage verification scripts
- **Generated:** No (committed)
- **Committed:** Yes
- **Key file:** `run_tests_with_coverage.sh` — Runs all tests and enforces 100% coverage on 26 guarded files

## Build Targets

**GhostEditCore (Framework):**
- **Source:** `GhostEdit/Sources/*` except `main.swift`
- **Purpose:** Reusable framework with all logic (imported by GhostEdit app and tests)
- **SKIP_INSTALL:** YES (framework only used by linked app, not distributed separately)

**GhostEdit (Application):**
- **Source:** `GhostEdit/Sources/main.swift` + `GhostEdit/Assets.xcassets`
- **Dependencies:** Links GhostEditCore framework
- **Purpose:** Executable macOS app
- **Bundle ID:** com.ghostedit.app

**GhostEditTests (Unit Test Bundle):**
- **Source:** `GhostEditTests/*.swift`
- **Dependencies:** Links GhostEditCore framework
- **Purpose:** Unit tests (no app host)
- **Bundle ID:** com.ghostedit.tests

---

*Structure analysis: 2026-02-26*
