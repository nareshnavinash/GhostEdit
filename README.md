# GhostEdit

GhostEdit is a native macOS menu bar app that fixes selected text in any app using a local CLI provider.

![GhostEdit launch preview](remotion/out/GitHubSocialPreview.png)

## Trailer

<video src="remotion/out/LaunchTrailer.mp4" controls preload="metadata"></video>

Direct download: [LaunchTrailer.mp4](remotion/out/LaunchTrailer.mp4)

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
- Preserves static tokens during correction (mentions, emojis, URLs, emails, file paths, inline code) via placeholder protection + retry
- Menu bar state indicator:
  - ![Idle menubar icon](remotion/out/MenuBarIconIdle.png) idle
  - ![Processing menubar icon](remotion/out/MenuBarIconProcessing.png) processing

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

## Protected Tokens During Correction

To keep platform-specific syntax intact (especially in Slack), GhostEdit replaces static tokens with placeholders before sending text to the model, then restores them after correction.

Protected token types:
- Mentions: `@name`, `@<id>`, and `<@id>`
- Emojis: `:hat:`, `:cat:`, etc.
- URLs: `https://...`
- Email addresses: `name@company.com`
- File paths:
  - absolute/relative Unix paths like `/tmp/file.txt`, `./notes/todo.md`
  - folder/file-style paths like `docs/readme.md`
- Inline code spans: `` `git status` ``

Failure behavior:
- If the model edits/removes placeholder tokens, GhostEdit retries once automatically.
- If the retry still fails token validation, GhostEdit shows an explicit error and does not paste a corrupted result.

Practical effect:
- Grammar/spelling/punctuation are still corrected.
- Static items are kept exactly as typed so links, mentions, emojis, and paths survive correction.

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
  - `GhostEdit/Sources/AccessibilitySupport.swift`
  - `GhostEdit/Sources/SettingsLayoutSupport.swift`
  - `GhostEdit/Sources/TokenPreservationSupport.swift`

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

By default, the build script uses ad-hoc signing with a stable designated requirement (`identifier "com.ghostedit.app"`). This helps macOS treat app updates as the same trusted app for Accessibility more reliably than cdhash-based ad-hoc signing.

For the most reliable persistence of Accessibility trust across updates, use a consistent real signing identity (Developer ID or Apple Development).

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
