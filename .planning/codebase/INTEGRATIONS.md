# External Integrations

**Analysis Date:** 2026-02-26

## APIs & External Services

**AI Grammar Correction (CLI-based):**
- **Claude** (Anthropic)
  - What it's used for: AI-powered grammar, spelling, and style correction (primary provider)
  - CLI Tool: `claude` executable (default in config)
  - Authentication: OAuth token via `claude auth login`
  - Auth storage: `~/.claude/` (managed by official Claude CLI)
  - Config reference: `CLIProvider.claude` enum in `ConfigManager.swift`
  - Available models: claude-haiku-4-5, claude-sonnet-4-5, claude-sonnet-4-6, claude-opus-4-6 (+ aliases)
  - Default model: claude-haiku-4-5
  - Streaming support: Yes (via `--stream-json` flag in `PersistentCLISession.swift`)

- **Codex** (OpenAI)
  - What it's used for: Alternative AI correction provider
  - CLI Tool: `codex` executable
  - Authentication: Token via `codex login`
  - Auth storage: Managed by Codex CLI
  - Config reference: `CLIProvider.codex` enum
  - Available models: gpt-5-codex, gpt-5.3-codex, gpt-5
  - Default model: gpt-5-codex
  - Streaming support: No (fallback to standard mode in `ShellRunner.swift`)

- **Gemini** (Google)
  - What it's used for: Alternative AI correction provider
  - CLI Tool: `gemini` executable
  - Authentication: Token via `gemini` command
  - Auth storage: Managed by Gemini CLI
  - Config reference: `CLIProvider.gemini` enum
  - Available models: gemini-2.5-flash-lite, gemini-2.5-flash, gemini-2.5-pro, gemini-3-flash-preview, etc.
  - Default model: gemini-2.5-flash-lite
  - Streaming support: No (fallback to standard mode)

## Data Storage

**Local Persistent Storage:**
- **JSON Configuration Files** (stored in `~/.ghostedit/`)
  - `config.json` - User settings (provider, model, hotkeys, preferences)
    - Location: `configManager.configURL` in `ConfigManager.swift` line 355
    - Structure: `AppConfig` struct (codec strategy for dates: ISO8601)
  - `history.json` - Correction history (entries with input/output/provider/model/result)
    - Location: `configManager.historyURL` line 356
    - Structure: Array of `CorrectionHistoryEntry` (JSON-encoded with ISO8601 dates)
    - Managed by: `CorrectionHistoryStore.swift` (thread-safe with NSLock)
  - `prompt.txt` - Custom system prompt for AI correction
    - Location: `configManager.promptURL` line 354
    - Plain text file, loaded on startup
  - `profiles.json` - Tone presets and correction profiles
    - Location: `configManager.profilesURL` line 357

**Directory Structure:**
```
~/.ghostedit/
├── config.json          # AppConfig (provider, model, hotkeys, UI state)
├── history.json         # CorrectionHistoryEntry[] (limited to historyLimit entries)
├── prompt.txt           # Custom system prompt
└── profiles.json        # Tone presets
```

**Legacy Migration:**
- Old directory: `~/.grammarfixer/` (migrated to `~/.ghostedit/` on first launch)
- Migration logic in: `ConfigManager.swift` lines 467-475

**Databases:**
- No external database (all data stored locally as JSON files)
- No SQL or persistent store framework (SQLite, Core Data, etc.)

**File Storage:**
- Local filesystem only
- No cloud storage integration
- Temporary files for shell I/O in `/tmp/` (session markers)
- Config files in user home directory (`~/.ghostedit/`)

**Caching:**
- None detected (no caching framework)
- History acts as implicit cache of previous corrections

## Authentication & Identity

**Auth Provider:**
- Custom - Each AI provider (Claude, Codex, Gemini) manages its own authentication
- No centralized auth system

**Authentication Approach:**
- Users run CLI provider auth commands in terminal (e.g., `claude auth login`)
- Credentials stored by respective CLI tools in their default locations
- GhostEdit does NOT manage or store credentials directly
- Path resolution in: `ShellRunner.swift` `resolveCLIPath()` method (lines 369-414)
- Auth validation in: `ShellRunner.swift` `authenticationRequired` error case (line 17)

**Environment Variables:**
- `PATH` - System PATH is used to discover CLI tools
- Provider-specific paths configurable via `config.json`:
  - `claudePath` - Custom path to claude executable
  - `codexPath` - Custom path to codex executable
  - `geminiPath` - Custom path to gemini executable
- If paths empty, CLI tools are discovered from `$PATH` at runtime

## Monitoring & Observability

**Error Tracking:**
- None detected (no Sentry, Crashlytics, or error reporting service)
- Local error logging only

**Logging:**
- Developer console built-in (DeveloperConsoleController in `AppDelegate.swift` lines 1871-2001)
- Logs stored in memory during session
- Categories: CLI resolution, token protection, token restoration, accessibility, shell execution
- Log viewer accessible via menu > Advanced > Developer Console
- Categories: `.cliResolution`, `.tokenProtection`, `.tokenRestoration`, etc. in `DeveloperModeSupport.swift`

**Observability:**
- No external metrics or analytics
- Local statistics only: correction counts, token usage estimation
- Statistics stored in `CorrectionStatisticsSupport.swift`

## CI/CD & Deployment

**Hosting:**
- Self-hosted: Users download .app from GitHub Releases
- GitHub Pages optional (not configured in codebase)

**CI Pipeline:**
- Git hooks (`.githooks/`) run on pre-commit and pre-push
- Hooks execute: `scripts/run_tests_with_coverage.sh`
- Tests run on each commit: All 432+ tests with 100% coverage enforcement
- No external CI service (GitHub Actions, CircleCI, etc.) detected

**Release Process:**
- Manual release via `gh release create vX.Y.Z-beta.N`
- Version bump in `project.pbxproj` (MARKETING_VERSION + CURRENT_PROJECT_VERSION, 2 occurrences each)
- Build command: `xcodebuild build -project GhostEdit.xcodeproj -scheme GhostEdit -configuration Release`
- Installation: Copy built .app to `/Applications/GhostEdit.app`, code-sign with `codesign --force --deep --sign -`

## Environment Configuration

**Required Environment Variables:**
- None required at runtime (all configured via UI or `config.json`)
- `PATH` - Used to discover CLI tools (implicit dependency)

**Optional Environment Variables:**
- `HOME` - User home directory (defaults to current user)

**Secrets Location:**
- No secrets stored in GhostEdit codebase
- Secrets managed by external CLI tools:
  - Claude credentials: `~/.claude/` (managed by Claude CLI)
  - Codex credentials: Managed by Codex CLI
  - Gemini credentials: Managed by Gemini CLI
- Settings export/import in: `SettingsExportSupport.swift` (no credential export)

**Key Configuration Files:**
- `config.json` - Provider selection, model, timeout, UI preferences
  - Load/save in: `ConfigManager.swift` lines 377-419, 421-465
- `prompt.txt` - Custom system prompt
  - Used in: `ShellRunner.swift` line 119 (default prompt if empty)
- `profiles.json` - Tone presets (casual, professional, academic, slack)
  - Profile prompts in: `ConfigManager.swift` lines 129-144

## Webhooks & Callbacks

**Incoming:**
- None detected (menu bar app, no server endpoints)

**Outgoing:**
- None detected (no webhooks to external services)

**Update Check:**
- Manual check to GitHub Releases page (not automated API call)
- Default release URL hardcoded: `https://github.com/nareshnavinash/GhostEdit/releases/latest`
  - In: `UpdateCheckSupport.swift` line 11
- Version comparison logic: Semantic versioning comparison
- No automatic background update checking (user-initiated only)

## Network Communication

**Protocol:**
- CLI tools handle all network communication
- GhostEdit communicates via subprocess (stdin/stdout/stderr)
- No direct HTTP/REST/WebSocket from GhostEdit

**Process Communication:**
- **ShellRunner.swift**: Spawns CLI tool processes and handles I/O
  - Error handling for subprocess failures (line 7-32)
  - Timeout handling: `timedOut(seconds: Int)` error (configurable in settings)
  - Persistent session via `PersistentCLISession.swift` for streaming mode

- **Streaming Mode** (`PersistentShellSession.swift`):
  - CLI tool stays alive between corrections
  - JSON streaming output (`--stream-json` flag for claude)
  - Used for real-time preview with character-level diff
  - Spawned in: `ShellRunner.spawnPersistentSession()` line 91

- **Non-streaming Mode**:
  - CLI tool spawned fresh for each correction
  - Process exits after response
  - Fallback for providers without streaming support (Codex, Gemini)

## System Integration

**Accessibility Framework:**
- macOS Accessibility API via `ApplicationServices`
- Used to: Copy/paste text from any system text field
- Implementation in: `AccessibilityTextSupport.swift`, `AccessibilitySupport.swift`
- Requires: User grants GhostEdit accessibility permission in System Preferences

**Hotkey System:**
- Global hotkey registration via Carbon.HIToolbox
- Hotkey configurable in settings (default: Cmd+E)
- Implementation in: `HotkeyManager.swift`, `HotkeySupport.swift`
- Requires: User grants GhostEdit accessibility permission

**Clipboard:**
- `NSPasteboard` for clipboard I/O (Copy/paste result)
- Fallback method if AX API unavailable
- Implementation in: `ClipboardManager.swift`

**Launch at Login:**
- macOS ServiceManagement for login item registration
- Implementation in: `LaunchAtLoginManager.swift`
- Managed via system preferences, not file-based

---

*Integration audit: 2026-02-26*
