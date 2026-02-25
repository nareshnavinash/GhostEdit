# GhostEdit Architecture

## Targets
| Target | Type | Sources | Bundle ID |
|--------|------|---------|-----------|
| GhostEditCore | Framework | All Sources except main.swift (32 files) | com.ghostedit.core |
| GhostEdit | App | main.swift + Assets | com.ghostedit.app |
| GhostEditTests | Unit Tests | GhostEditTests/ (26 files) | com.ghostedit.tests |

## Source Files (GhostEdit/Sources/) — 33 files, ~9K lines

### AppDelegate.swift (~4,600 lines) — The Monolith
Contains ALL window controllers and the main app delegate.

| Class/Component | Lines | Purpose |
|----------------|-------|---------|
| AppDelegate | 6-1856 | Menu bar, hotkey, text processing pipeline |
| DeveloperConsoleController | 1871-2001 | Dev log viewer |
| DiffPreviewController | 2003-2151 | Side-by-side diff with Apply/Cancel |
| StreamingPreviewController | 2153-2647 | Live streaming, char diff, change nav, stats |
| LineNumberRulerView | 2651-2736 | NSRulerView for line numbers |
| SettingsWindowController | 2738-3636 | Tabbed settings (General/Hotkey/Behavior/Advanced) |
| HistoryWindowController | 3638-4219 | Table with search, filter, status badges |
| HistoryCopyTableView | 4221-4240 | NSTableView subclass for copy support |
| HUDOverlayController | 4242-4556 | Ghost HUD with tint, spinner, slide animation |
| CGPath extension | 4558-4600 | SVG path parsing for ghost icon |

### AppDelegate Key Methods
| Method | Lines | Purpose |
|--------|-------|---------|
| applicationDidFinishLaunching | 51-76 | Bootstrap, register hotkey, start observers |
| configureStatusItem | 85-315 | Build entire menu bar menu |
| handleHotkeyTrigger | 579-626 | Entry point for correction flow |
| processSelectedText | 715-952 | Non-streaming correction pipeline |
| launchStreamingRequest | 954-1007 | Streaming correction pipeline |
| pasteViaClipboard | 1102-1143 | Clipboard-based paste fallback |
| recordHistoryEntry | 1820-1846 | Write to history store |
| refreshHistoryWindowIfVisible | 1784-1790 | Reload history data (reversed, newest first) |
| showSettingsWindow | 1339-1364 | Open/create settings |
| performUpdateCheck | 1457-1503 | GitHub version check |
| runWritingCoach | 1532-1585 | Writing coach LLM call |

### Support Modules (pure logic, no AppKit)
| File | Lines | Purpose |
|------|-------|---------|
| ConfigManager.swift | 478 | Config storage, provider/model definitions |
| ShellRunner.swift | 682 | CLI execution, streaming, token preservation |
| ClipboardManager.swift | 169 | Copy/paste simulation |
| HotkeyManager.swift | 99 | Carbon event hotkey registration |
| PersistentCLISession.swift | 542 | Keep CLI warm for fast responses |
| PersistentShellSession.swift | 214 | Shell process management |
| TokenPreservationSupport.swift | 281 | Protect emoji/URLs from LLM mangling |
| WritingCoachSupport.swift | 244 | Parse writing insights |
| DiffSupport.swift | 225 | Myers diff (word + char level) |
| ClaudeRuntimeSupport.swift | 143 | Claude CLI path resolution |
| HUDOverlaySupport.swift | 111 | HUD state/layout constants |
| HotkeySupport.swift | 108 | Key code to display string |
| CorrectionStatisticsSupport.swift | 108 | Usage statistics |
| CorrectionHistoryStore.swift | 94 | JSON-backed history |
| AccessibilityTextSupport.swift | 80 | AX API text replacement |
| DeveloperModeSupport.swift | 67 | Log formatting |
| MenuBarIconSupport.swift | 59 | Icon rendering |
| HistoryTableModel.swift | 59 | Table row model |
| StreamingPreviewSupport.swift | 58 | Streaming status text |
| AppProfileSupport.swift | 58 | Per-app LLM profiles |
| TooltipSupport.swift | 57 | Menu tooltip formatting |
| PartialCorrectionSupport.swift | 55 | Sentence-level correction |
| TokenEstimationSupport.swift | 54 | Token count estimation |
| HistoryCSVExporter.swift | 53 | CSV export |
| UpdateCheckSupport.swift | 50 | Semver comparison |
| SettingsExportSupport.swift | 48 | Settings import/export |
| FallbackSupport.swift | 37 | Model fallback logic |
| WritingCoachLayoutSupport.swift | 31 | Coach panel layout |
| LaunchAtLoginManager.swift | 27 | Login item management |
| SettingsLayoutSupport.swift | 16 | Settings UI constants |
| AccessibilitySupport.swift | 11 | AX guidance text |

## Test Files (GhostEditTests/) — 26 files, ~5,700 lines
Each guarded source file has a corresponding test file. Test naming: `{SourceFile}Tests.swift`.
Total tests: 437+, all must pass with 100% line coverage on guarded files.

## Coverage Gate
26 files require 100% line coverage. See CLAUDE.md or `scripts/run_tests_with_coverage.sh` REQUIRED_FILES array.
7 files are exempt: AppDelegate, ClipboardManager, HotkeyManager, LaunchAtLoginManager, PersistentCLISession, PersistentShellSession, main.

## Config Location
`~/.ghostedit/` containing: config.json, prompt.txt, history.json, profiles.json
