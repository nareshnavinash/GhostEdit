# Architecture

**Analysis Date:** 2026-02-26

## Pattern Overview

**Overall:** Layered macOS menu bar application with strict separation between UI orchestration and pure-logic support modules. AppKit UI lives in AppDelegate, all business logic lives in testable Support enums and final classes.

**Key Characteristics:**
- AppDelegate is a monolithic orchestrator that manages hotkey events, UI state, and text processing pipelines
- Support modules are pure-logic enums with static methods — no AppKit imports, 100% testable
- Two-target architecture: GhostEditCore (all logic except main.swift) and GhostEdit (UI container)
- Explicit separation between AppKit UI code and reusable business logic
- Persistent sessions and background threads handle long-running CLI operations

## Layers

**Presentation (UI Orchestration):**
- Purpose: Menu bar icon, status menu, hotkey listening, window management (Settings/History/HUD/DeveloperConsole)
- Location: `GhostEdit/Sources/AppDelegate.swift` (lines 6-1856 for AppDelegate class; lines 2174-4556 for window controllers)
- Contains: AppDelegate (menu/hotkey/status), DeveloperConsoleController, DiffPreviewController, StreamingPreviewController, SettingsWindowController, HistoryWindowController, HUDOverlayController, LiveFeedbackController
- Depends on: ConfigManager, ShellRunner, CorrectionHistoryStore, ClipboardManager, HotkeyManager, all Support modules
- Used by: main.swift entry point

**Domain Logic (Pure Support Modules):**
- Purpose: Reusable, testable algorithms for token preservation, diff computation, spell checking, streaming, statistics
- Location: `GhostEdit/Sources/*Support.swift` (23 files)
- Contains: TokenPreservationSupport, DiffSupport, SpellCheckSupport, TokenEstimationSupport, StreamingPreviewSupport, WritingCoachSupport, AccessibilityTextSupport, LiveFeedbackSupport, etc.
- Depends on: Foundation only (no AppKit)
- Used by: AppDelegate, ShellRunner, tests

**System Integration:**
- Purpose: OS-level interactions — clipboard, hotkey registration, accessibility APIs, process management
- Location:
  - `GhostEdit/Sources/ClipboardManager.swift` — NSPasteboard, CGEvent simulation
  - `GhostEdit/Sources/HotkeyManager.swift` — Carbon.HIToolbox event registration
  - `GhostEdit/Sources/AccessibilitySupport.swift` — Accessibility permission guidance
  - `GhostEdit/Sources/AccessibilityTextSupport.swift` — AXUIElement text read/write
  - `GhostEdit/Sources/HotkeySupport.swift` — Hotkey display formatting
  - `GhostEdit/Sources/MenuBarIconSupport.swift` — NSImage icon generation
- Depends on: AppKit, Carbon, CoreGraphics, ApplicationServices
- Used by: AppDelegate for clipboard operations, hotkey registration, app activation

**Configuration & Persistence:**
- Purpose: Config file loading/saving, history storage, prompt management, provider selection
- Location:
  - `GhostEdit/Sources/ConfigManager.swift` — JSON config at ~/.ghostedit/config.json, prompt.txt, profiles.json
  - `GhostEdit/Sources/CorrectionHistoryStore.swift` — JSON history at ~/.ghostedit/history.json with locking
  - `GhostEdit/Sources/AppProfileSupport.swift` — Per-app prompt/model overrides
- Depends on: Foundation (FileManager, JSONEncoder/Decoder)
- Used by: AppDelegate on startup, ShellRunner for provider/model selection, HistoryWindowController for display

**CLI Execution:**
- Purpose: Spawn and communicate with external CLI (Claude/Gemini/Codex), handle streaming/non-streaming modes
- Location:
  - `GhostEdit/Sources/ShellRunner.swift` — High-level API for correctTextPreservingTokens() and correctTextStreaming()
  - `GhostEdit/Sources/PersistentCLISession.swift` — Keep-alive process management for faster response times
  - `GhostEdit/Sources/PersistentShellSession.swift` — Low-level shell/pipe communication
- Depends on: Foundation (Process, Pipe), ConfigManager
- Used by: AppDelegate for text corrections

## Data Flow

**Main Correction Flow (Non-Streaming):**

1. Hotkey pressed (Cmd+E) → `HotkeyManager` invokes `handleHotkeyTrigger()`
2. `handleHotkeyTrigger()` → Guard checks (accessibility permission, not already processing)
3. Try AX read: `AccessibilityTextSupport.readSelectedText()` → if U+FFFC detected or fails, fall back to clipboard copy
4. If clipboard: Set sentinel, simulate Cmd+C via `ClipboardManager.simulateCopyShortcut()` → poll clipboard in `waitForCopiedText()` until text differs from sentinel
5. Once text captured: `processSelectedText()` → Load config + per-app profile overrides
6. Run `ShellRunner.correctTextPreservingTokens()` →
   - `TokenPreservationSupport.protectTokens()` replaces URLs, emails, code, @mentions, emojis with placeholders
   - Append protection instruction to system prompt
   - Pass to CLI (Claude/Gemini/Codex) via `PersistentCLISession.sendMessage()`
   - Restore placeholders in response via `TokenPreservationSupport.restoreTokens()`
7. Record history: `CorrectionHistoryStore.append()` with succeeded: true/false
8. Apply result: `applyCorrectedText()` → Try AX replace first, fall back to clipboard paste
9. HUD shows success count, status bar updates timestamp

**Streaming Flow:**

1. Steps 1-5 same as non-streaming
2. Instead of `correctTextPreservingTokens()`, call `ShellRunner.correctTextStreaming()`
3. `StreamingPreviewController` created, accumulates streamed chars, displays live in diff view
4. `StreamingPreviewSupport.charDiff()` highlights changes character-by-character
5. User can accept/cancel → if accept, paste via `applyCorrectedText()` same as above

**Live Feedback Flow:**

1. `LiveFeedbackController` spawned in background if `liveFeedbackEnabled: true`
2. Monitors Slack (via accessibility), extracts message text periodically
3. Runs lightweight checks: `SpellCheckSupport.spellCheck()`, `LiveFeedbackSupport.analyzeText()`
4. Displays popover widget with issue count + badges (spelling, grammar, style)
5. User accepts → pulls full correction via `ShellRunner.correctTextStreaming()`

**Error Handling Flow:**

1. `ShellRunner` raises `ShellRunnerError` (CLI not found, auth required, timeout, empty response, etc.)
2. `handleProcessingError()` pattern-matches error type → determines if user should switch model, re-auth, or check config.json
3. Shows user alert, updates status, records history with succeeded: false
4. HUD shows error state

## Key Abstractions

**Support Enum Modules (23 total):**

Pattern: All Support modules are enums with static methods + private helpers. Examples:
- `TokenPreservationSupport` — regex-based token extraction, placeholder generation, token restoration
- `DiffSupport` — word-level diff (for summaries) and character-level diff (for display highlighting)
- `SpellCheckSupport` — Hunspell-based spell check + grammar rules
- `WritingCoachSupport` — Writing style analysis with tone presets
- `StreamingPreviewSupport` — Accumulate streamed response, compute char-level diffs
- `ConfigManager` enum extensions — Computed properties for provider/model resolution

**Controller Classes (inside AppDelegate.swift):**

- `AppDelegate` — Main state machine, menu bar setup, hotkey/copy/paste orchestration
- `DeveloperConsoleController` — Log viewer for debugging (enabled via `developerMode: true`)
- `DiffPreviewController` — Side-by-side diff window (before/after)
- `StreamingPreviewController` — Live streaming preview with character-level highlighting
- `SettingsWindowController` — Tabbed UI (General/Hotkey/Behavior/Advanced)
- `HistoryWindowController` — Searchable/filterable history table
- `HUDOverlayController` — Ghost overlay with success/error animations
- `LiveFeedbackController` — Background monitor for app-specific feedback

**Manager Classes:**

- `ConfigManager` — Loads/saves ~/.ghostedit/config.json with validation
- `CorrectionHistoryStore` — Thread-safe JSON persistence for history entries
- `ClipboardManager` — Snapshot/restore, read/write plain text and HTML, simulate Cmd+C/Cmd+V via CGEvent
- `HotkeyManager` — Carbon event handler registration for base hotkey + shift variant
- `ShellRunner` — CLI discovery, persistent session spawning, streaming/non-streaming text correction
- `PersistentCLISession` — Keep-alive process that reads/writes via pipes (faster than process spawn per request)

**Data Models:**

- `CorrectionHistoryEntry` — Codable struct: id, timestamp, originalText, generatedText, provider, model, durationMilliseconds, succeeded
- `AppConfig` — Codable: all user settings (provider, model, timeout, hotkey, launch-at-login, history limit, etc.)
- `CLIProvider` enum — .claude, .codex, .gemini with model lists and auth/path helpers
- `ProtectedToken` — pair of placeholder + originalToken
- `TokenProtectionResult` — protectedText + token array

## Entry Points

**main.swift:**
- Location: `GhostEdit/Sources/main.swift`
- Triggers: App launch (user opens GhostEdit.app)
- Responsibilities: Creates NSApplication, sets AppDelegate, calls app.run()

**AppDelegate.applicationDidFinishLaunching:**
- Location: `GhostEdit/Sources/AppDelegate.swift` (lines 54-81)
- Triggers: After main.swift sets up app
- Responsibilities:
  - Set accessory activation policy (menu bar only, no dock icon)
  - Bootstrap config/history files
  - Request accessibility permission
  - Register hotkey
  - Start live feedback if enabled

**HotkeyManager.registerWithVariant:**
- Location: `GhostEdit/Sources/HotkeyManager.swift`
- Triggers: During AppDelegate setup, and when user changes hotkey in Settings
- Responsibilities:
  - Register base hotkey + auto-derive shift variant with Carbon event handler
  - Invoke user handler on keypress

**handleHotkeyTrigger:**
- Location: `GhostEdit/Sources/AppDelegate.swift` (lines 879-926)
- Triggers: When user presses hotkey (Cmd+E or custom)
- Responsibilities: Copy selected text, trigger processSelectedText

## Error Handling

**Strategy:** Fail-safe with graceful degradation and user-facing alerts.

**Patterns:**

1. **Accessibility Path Failures:**
   - Try AX read text → if fails or contains U+FFFC (emoji placeholders), fall back to clipboard copy
   - Try AX write text → if fails, fall back to clipboard paste
   - Timeout on clipboard wait (1.4s), then try next copy strategy or fail

2. **CLI Errors:**
   - `ShellRunnerError` enum cases: .cliNotFound, .authenticationRequired, .launchFailed, .processFailed, .timedOut, .emptyResponse, .protectedTokensModified
   - Each error has specific `errorDescription` with actionable advice (e.g., "Run `claude auth login` in Terminal")
   - History recorded as succeeded: false for debugging

3. **Token Protection Failures:**
   - If restored tokens don't match placeholders exactly, record failed attempt and alert user
   - Shows diff of what went wrong so user can manually re-check

4. **Config File Errors:**
   - Missing ~/.ghostedit/ → bootstrap creates empty config.json + prompt.txt
   - Corrupted JSON → fall back to defaults via `loadConfig()` decoder error handling

5. **History Persistence:**
   - Thread-safe NSLock around read/write operations
   - Atomic writes with .atomic flag
   - If write fails, continue anyway (don't block user)

## Cross-Cutting Concerns

**Logging:**
- `DeveloperModeLogger` protocol (implemented by AppDelegate)
- `DeveloperModeSupport` enum provides logging categories (.textCapture, .pasteBack, .streaming, etc.)
- Console window shows timestamped log entries if `developerMode: true` in config
- No logging in Support modules (pure logic)

**Validation:**
- `ConfigManager.loadConfig()` deserializes with defaults for missing fields
- `TokenPreservationSupport` validates placeholders match original positions before restoring
- `ShellRunner` validates CLI path exists before launch
- History entries validated for Codable conformance at serialization

**Authentication:**
- Each CLI provider (.claude, .codex, .gemini) manages its own auth (stored in ~/.{provider}/)
- If auth fails, error handler suggests running provider's auth command
- No credentials stored in GhostEdit config — delegates to CLI

**Accessibility:**
- Checked at app launch and before each hotkey trigger
- Fallback chain: try AX → clipboard → fail
- User prompted to enable in System Settings if missing
- Works around app-specific AX limitations (Slack emoji U+FFFC, etc.)

**Performance:**
- Persistent CLI session pre-spawned at startup for <200ms first response
- Token protection run in background on correction thread (not blocking UI)
- Live feedback in separate background controller
- Streaming response processed character-by-character as it arrives
- Clipboard snapshot/restore batched to minimize HID event calls

---

*Architecture analysis: 2026-02-26*
