# GhostEdit

GhostEdit is a native macOS menu bar app that fixes selected text in any app using a local CLI provider.

## Features

- Global hotkey (`Command + E` by default)
- Configurable global hotkey in **Settings...**
- Works in background (no Dock icon)
- Configurable prompt in `~/.ghostedit/prompt.txt`
- Provider switch in **Settings...**: Claude, Codex, Gemini
- Model switch in **Settings...** (full provider model lists + custom model)
- Lowest-model defaults when switching providers:
  - Codex: `gpt-5-codex`
  - Gemini: `gemini-2.5-flash-lite`
- Launch at login toggle in **Settings...**
- Configurable correction history size (`History N`, default `200`) in **Settings...**
- History viewer (`History...`) uses a wrapped table with headers and supports per-cell copy (`Cmd+C`) and CSV export
- Writing coach action: **Sharpen My Writing Style** analyzes your past originals and shows positives plus improvements
- Busy/unavailable model guidance in notifications and settings hint
- Menu bar state indicator:
  - `ⓖ` idle
  - `🤓` processing

## Build and Run (Local)

1. Install dependencies:

```bash
brew install xcodegen
```

2. Generate Xcode project:

```bash
xcodegen generate --spec project.yml
```

3. Open in Xcode:

```bash
open GhostEdit.xcodeproj
```

4. Set your signing team and run.

## First Launch Files

GhostEdit creates:

- `~/.ghostedit/prompt.txt`
- `~/.ghostedit/config.json`
- `~/.ghostedit/history.json`

If `~/.grammarfixer` exists from older builds, GhostEdit migrates it to `~/.ghostedit` automatically.

Default `config.json`:

```json
{
  "claudePath": "",
  "codexPath": "",
  "geminiPath": "",
  "provider": "claude",
  "model": "haiku",
  "hotkeyKeyCode": 14,
  "hotkeyModifiers": 256,
  "timeoutSeconds": 30,
  "launchAtLogin": false,
  "historyLimit": 200
}
```

Notes:
- `provider` controls which CLI is used.
- `model` is shared and interpreted by the selected provider.
- `claudePath`, `codexPath`, and `geminiPath` can be empty if auto-discovery works.
- If auto-discovery fails, set an absolute path for that provider.
- If a model is busy/fails, switch models in **Settings...** and retry.
- `historyLimit` controls how many recent corrections are kept in `history.json`.

## Mandatory Tests and Coverage

Run the full test+coverage gate:

```bash
./scripts/run_tests_with_coverage.sh
```

This gate enforces:
- Unit tests must pass.
- 100% line coverage on:
  - `GhostEdit/Sources/ConfigManager.swift`
  - `GhostEdit/Sources/ShellRunner.swift`
  - `GhostEdit/Sources/ClaudeRuntimeSupport.swift`
  - `GhostEdit/Sources/CorrectionHistoryStore.swift`
  - `GhostEdit/Sources/HistoryTableModel.swift`
  - `GhostEdit/Sources/HistoryCSVExporter.swift`
  - `GhostEdit/Sources/HotkeySupport.swift`
  - `GhostEdit/Sources/WritingCoachSupport.swift`

The same gate is wired into:
- `.githooks/pre-commit`
- `.githooks/pre-push`

Enable repo hooks locally:

```bash
git config core.hooksPath .githooks
```

## Accessibility Permission

GhostEdit sends `Cmd+C` and `Cmd+V` programmatically. Grant permission at:

- System Settings > Privacy & Security > Accessibility

## Provider Authentication

If authentication expires, GhostEdit will show a prompt with the command to run:

- Claude: `claude auth login`
- Codex: `codex login`
- Gemini: `gemini`

## Create Installable Artifacts

Build signed release artifacts (`.zip` and `.dmg`):

```bash
./scripts/build_release.sh
```

Optional: sign with a specific Developer ID identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_release.sh
```

Artifacts are generated in:

- `build/release/GhostEdit-macOS.zip`
- `build/release/GhostEdit-macOS.dmg`

For true out-of-the-box install on other Macs (no Gatekeeper warning), notarize the DMG:

```bash
NOTARY_PROFILE="your-notary-profile" ./scripts/notarize_release.sh build/release/GhostEdit-macOS.dmg
```

`NOTARY_PROFILE` is a keychain profile created with Apple `notarytool`.

## GitHub Publishing

A workflow is included at `.github/workflows/release.yml`.

- Push a tag like `v1.0.0`
- Workflow builds and uploads `.zip` and `.dmg` to the GitHub Release
- For notarized releases, add signing/notary steps and secrets to the workflow

## Privacy and Repo Safety

This repo does not store local user prompt/config files from `~/.ghostedit`.

Before pushing, verify no local secrets were added:

```bash
rg -n "(api[_-]?key|token|secret|password|PRIVATE KEY)" .
```
