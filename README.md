# GhostEdit

**Free, open-source offline grammar checker for macOS. Fix grammar, spelling, and punctuation in any app with a single hotkey — powered by Apple Intelligence, Claude, OpenAI Codex, or Gemini. The best free macOS grammar correction tool with on-device AI and no subscriptions.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-black.svg)](https://github.com/nareshnavinash/GhostEdit/releases)
[![Latest Release](https://img.shields.io/github/v/release/nareshnavinash/GhostEdit)](https://github.com/nareshnavinash/GhostEdit/releases/latest)

> GhostEdit is a lightweight macOS menu bar app that corrects grammar, spelling, and punctuation in any text field system-wide. Press a hotkey and your text is fixed instantly — using Apple Intelligence on-device or your choice of Claude, Codex, or Gemini. No accounts, no subscriptions, no data leaves your Mac.

![GhostEdit launch preview](remotion/out/TwitterBanner.png)

## Installation

Download the latest `.dmg` from the [Releases page](https://github.com/nareshnavinash/GhostEdit/releases/latest), drag GhostEdit to Applications, and grant Accessibility permission.

### 🛠 macOS Installation & Troubleshooting

Because GhostEdit is not currently signed with an Apple Developer certificate, macOS Gatekeeper may flag it and show an error saying: **"Apple could not verify 'GhostEdit' is free of malware"** or **"'GhostEdit' is damaged and can't be opened."**

If you encounter this error and only see a "Move to Bin" option, you can easily bypass it using one of the following methods:

#### Method 1: Using Terminal (Recommended)
This removes the macOS "quarantine" flag from the downloaded app, allowing it to run normally.

1. Unzip the downloaded release and move `GhostEdit.app` to your **Applications** folder.
2. Open the **Terminal** app.
3. Paste the following command and press Enter:
   xattr -cr /Applications/GhostEdit.app

You can now double-click the app to open it normally! (You only need to do this once).

#### Method 2: System Settings
1. Attempt to open the app normally by double-clicking it (this triggers the error). Click Done.
2. Open your Mac's System Settings and go to Privacy & Security.
3. Scroll down to the Security section.
4. You will see a message saying that "GhostEdit" was blocked. Click the Open Anyway button next to it.
5. Enter your Mac password or use Touch ID, and click Open on the final prompt.

## Trailer

![GhostEdit launch trailer](remotion/out/LaunchTrailer.gif)

## Why GhostEdit?

- **No account required** uses AI CLIs you already have installed (Claude, Codex, Gemini). No sign-ups, no subscriptions.
- **Privacy-first** text never leaves your machine through a third-party service. Corrections run through your own local CLI. No telemetry, no data collection.
- **Free and open source** no premium tiers, no word limits, no feature gates. Full grammar correction, writing coaching, and history all included.
- **Works everywhere** correct text in any macOS app: Slack, Notion, VS Code, Mail, Pages, or any text field. One hotkey, any app.
- **Bring your own AI** switch between Claude, OpenAI Codex, and Gemini from Settings. Pick the model that works best for you.
- **On-device grammar** Apple Foundation Models and Harper provide instant local corrections with no API calls needed.

## How It Works

1. **Press cmd+E** for an instant local fix — Apple Intelligence (macOS 26+) or Harper corrects spelling and grammar offline in under 100ms
2. **Press cmd+shift+E** for a deep LLM fix — Claude, Codex, or Gemini rewrites and polishes your text with full contextual understanding
3. **See what changed** — an optional diff preview highlights every correction before it's applied, and you can undo any fix instantly

No setup needed for local fixes. For LLM fixes, install any supported AI CLI and GhostEdit auto-detects it.

## Features

### v6.0.0 Highlights

- **Apple Foundation Models integration**: On-device grammar correction using Apple's built-in language models — no API keys, no network, instant results
- **Harper bundled grammar/spell checker**: Fast, offline grammar and style checking via the Harper linting engine for comprehensive rule-based detection
- **Redesigned floating widget**: App icon with a colored status dot indicator, positioned below the active text field (never overlapping your typing)
- **Draggable widget**: Drag the widget anywhere on screen — it stays where you put it until you switch apps
- **Click-to-fix with accept/ignore**: Each issue row shows action buttons — accept the fix, ignore once, or always ignore a word
- **Acronym and proper noun awareness**: Automatically filters out acronyms (LLM, API, NASA) and proper nouns from spelling issues
- **Dual hotkey system**: Base hotkey triggers fast local fixes (Harper + NSSpellChecker), Shift+hotkey triggers full LLM correction
- **Per-word cursor stability**: Fixes in Slack and other apps now apply word-by-word to preserve cursor position

### Core Features

- **Fire-and-forget correction**: Press the hotkey, switch to any app corrected text is pasted back automatically, even if the target app is in the background
- **Native HUD overlay**: A glossy floating ghost indicator shows "Working on it..." (with spectacles) and "Done!" (idle ghost), then fades away after 1 second
- **Smart paste-back**: Uses accessibility (AX) text replacement for native apps (no focus change needed), with delayed verification and automatic clipboard fallback for Electron apps (Slack, Discord, VS Code)
- **Multi-provider support**: Choose between Claude, OpenAI Codex, and Gemini — switch providers and models from Settings
- **Multi-language support**: Correct text in 30+ languages — auto-detect or pick a specific language in Settings
- **Tone presets**: Switch between Default, Casual, Professional, Academic, and Slack tones from the menu bar
- **Writing coach**: **Sharpen My Writing Style** analyzes your past corrections and shows what you do well plus areas to improve
- **Token preservation**: Mentions, emojis, URLs, emails, file paths, and inline code are preserved during correction
- **Correction history**: Browse, copy, and export past corrections as CSV
- **Statistics dashboard**: View correction counts, success rates, provider/model breakdown, and estimated token usage
- **Diff preview**: Optional word-level diff window with red/green highlights shows changes before applying — enable via Settings or `showDiffPreview` in config
- **Undo last correction**: Revert the most recent correction via menu bar
- **Auto-retry with fallback model**: If the selected model fails, GhostEdit automatically retries with the next available model
- **Per-app profiles**: Configure different tone, model, or provider per application via `~/.ghostedit/profiles.json`
- **Export/import settings**: Back up or transfer your full configuration (settings + prompt) as a single JSON file
- **Customizable prompt**: Tailor the AI instructions in `~/.ghostedit/prompt.txt`
- **Sound feedback**: Audio cues for success and error (configurable)
- **Success notifications**: Optional system notifications on successful corrections
- **Clipboard-only mode**: Correct text and place it on the clipboard without auto-pasting
- **Menu bar tooltip**: Shows a summary of the last correction (time, text preview, provider)
- **Token estimation**: Estimated cumulative token usage shown in Statistics
- **Live feedback**: Real-time spelling, grammar, punctuation, and style checking in any text field — a floating widget shows issues as you type with smart quotes, em-dash, and symbol replacement suggestions powered by macOS native text checking and Harper
- **Ignored words**: Permanently ignore specific words across sessions via the widget or `~/.ghostedit/ignored_words.json`
- **Version check support**: Compare your version against the latest release
- Global hotkey (`Command + E` by default), configurable in **Settings...**
- Works in background (no Dock icon)
- Launch at login toggle
- Menu bar state indicator:
  - ![Idle menubar icon](remotion/out/MenuBarIconIdle.png) idle
  - ![Processing menubar icon](remotion/out/MenuBarIconProcessing.png) processing

### Live Feedback

When enabled in **Settings > Behavior**, a floating widget appears near the active text field and checks your writing in real time using macOS built-in text checking — no AI API calls needed.

**What it detects:**

| Category | Examples |
|----------|----------|
| Spelling | Misspelled words with correction suggestions |
| Grammar | Subject-verb agreement, punctuation errors |
| Smart quotes | Straight `"..."` → curly `\u201c...\u201d` |
| Smart dashes | `--` → em-dash `\u2014` |
| Symbol replacement | `(c)` → `\u00a9`, `(tm)` → `\u2122` |
| Autocorrect | Common typos the system already knows |

The widget shows a colored status dot (green = clean, red = issues found). Click the widget to toggle the detail popover listing each issue with suggestions. Each issue row has action buttons: accept the fix, ignore once, or always ignore the word. Drag the widget anywhere — it stays put until you switch apps. Enable from **Settings > Behavior > Live Feedback** or set `"liveFeedbackEnabled": true` in config.

### Dual Hotkey: Local Fix vs LLM Fix

GhostEdit gives you two ways to fix text. The base hotkey (cmd+E) runs entirely on your Mac — no internet, no API keys, no delay. The shift variant (cmd+shift+E) sends text to a cloud AI for deeper rewrites. Most people use cmd+E for everyday typos and switch to cmd+shift+E only when they need serious polishing.

Here's how they compare:

| | **cmd+E** (Local Fix) | **cmd+shift+E** (LLM Fix) |
|---|---|---|
| **Speed** | Instant (< 100ms) | 2-5 seconds |
| **Network** | None (fully offline) | Requires AI CLI |
| **Engine** | Apple Intelligence (macOS 26+) or Harper + NSSpellChecker (macOS 13-25) | Claude, Codex, or Gemini |
| **Spelling** | Yes | Yes |
| **Grammar** | Yes (Apple Intelligence) / Basic (Harper) | Yes (contextual) |
| **Punctuation** | Yes (Apple Intelligence) / No (Harper) | Yes |
| **Rewrites** | Light corrections only | Full sentence restructuring |
| **Best for** | Quick typo fixes, Slack messages, emails | Polishing important text, deep rewrites |

For most day-to-day corrections (fixing typos in Slack, emails, quick notes), cmd+E handles it instantly. Use cmd+shift+E when you need deeper rewrites or the local fix didn't catch something.

### Apple Intelligence (macOS 26+)

On supported hardware, cmd+E uses Apple's on-device Foundation Models for grammar, spelling, and punctuation correction — no API keys, no network, instant results.

Why this matters:
- **No API keys** — works out of the box, nothing to configure
- **No internet required** — corrections run entirely on-device
- **No data leaves your Mac** — your text stays private, always
- **Instant results** — sub-100ms corrections, no waiting for a server

**Requirements:**
- macOS 26 (Tahoe) or later
- Apple Silicon (M1, M2, M3, or M4)
- 16 GB RAM or more
- Apple Intelligence enabled in **System Settings > Apple Intelligence & Siri**

**How to enable:**
1. Open **System Settings** > **Apple Intelligence & Siri**
2. Turn on **Apple Intelligence**
3. Wait for the on-device model to download (may take a few minutes on first enable)
4. GhostEdit automatically detects Apple Intelligence — no configuration needed

**Fallback behavior:** If Apple Intelligence is unavailable (older Mac, insufficient RAM, not enabled), cmd+E automatically falls back to Harper (grammar rules) + NSSpellChecker (spelling). Harper catches common grammar patterns but does not handle punctuation or contextual rewrites.

**Verify availability:** Enable Developer Mode in GhostEdit (menu bar > Developer Mode) and press cmd+E. The console will show whether the Foundation Model path or the Harper fallback was used.

### Prerequisites

You need at least one AI CLI installed for **cmd+shift+E** (LLM corrections):

| Provider | Install | Auth |
|----------|---------|------|
| Claude | `brew install claude` or [download](https://claude.com/claude-code) | `claude auth login` |
| OpenAI Codex | `npm install -g @openai/codex` | `codex login` |
| Gemini | `npm install -g @anthropic-ai/gemini` | `gemini` |

## Build from Source

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

## Configuration

GhostEdit creates these files on first launch:

- `~/.ghostedit/prompt.txt` AI prompt (editable)
- `~/.ghostedit/config.json` settings
- `~/.ghostedit/history.json` correction history

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
  "historyLimit": 200,
  "developerMode": false,
  "language": "auto",
  "tonePreset": "default",
  "soundFeedbackEnabled": true,
  "notifyOnSuccess": false,
  "clipboardOnlyMode": false,
  "showDiffPreview": false,
  "liveFeedbackEnabled": false,
  "diffPreviewDuration": 3
}
```

Notes:
- `provider` controls which CLI is used.
- `model` is shared and interpreted by the selected provider.
- `claudePath`, `codexPath`, and `geminiPath` can be empty if auto-discovery works.
- If auto-discovery fails, set an absolute path for that provider.
- If a model is busy/fails, GhostEdit automatically retries with the next available model.
- `historyLimit` controls how many recent corrections are kept in `history.json`.
- `language` can be `"auto"` (detect input language) or a specific code like `"en"`, `"es"`, `"fr"`, etc.
- `tonePreset` can be `"default"`, `"casual"`, `"professional"`, `"academic"`, or `"slack"`.
- `soundFeedbackEnabled` plays audio cues on success/error.
- `notifyOnSuccess` sends a macOS notification when a correction completes.
- `clipboardOnlyMode` places corrected text on the clipboard without pasting it back.
- `showDiffPreview` shows a word-level diff preview window before applying the correction.
- `liveFeedbackEnabled` enables real-time spelling, grammar, and style checking in a floating widget.
- `diffPreviewDuration` seconds to show the diff popup before auto-dismissing (1-30, default 3).

### Per-App Profiles

Create `~/.ghostedit/profiles.json` to customize settings per application:

```json
[
  {
    "bundleIdentifier": "com.tinyspeck.slackmacgap",
    "tonePreset": "slack"
  },
  {
    "bundleIdentifier": "com.apple.mail",
    "tonePreset": "professional",
    "model": "sonnet"
  }
]
```

Each profile can override `tonePreset`, `model`, and `provider` for a specific app (matched by bundle identifier).

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
- If the retry still fails, GhostEdit performs a best-effort restoration any placeholders the model preserved are restored, and the correction still succeeds.

Practical effect:
- Grammar/spelling/punctuation are still corrected.
- Static items are kept exactly as typed so links, mentions, emojis, and paths survive correction.

## Developer Mode

GhostEdit includes a **Developer Mode** that shows what happens behind the scenes during each text correction. When enabled, a live console window displays every step of the correction pipeline in real time.

### How to enable

- **Menu bar**: Click the GhostEdit menu bar icon > **Developer Mode** (toggles on/off)
- **Settings**: Check **Enable Developer Mode** in the Settings window
- **Config file**: Set `"developerMode": true` in `~/.ghostedit/config.json`

### What you see

The Developer Console shows timestamped, color-coded log entries for each phase:

| Phase | Description |
|-------|-------------|
| `TEXT_CAPTURE` | Selected text read via Accessibility or clipboard |
| `TOKEN_PROTECTION` | Mentions, emojis, URLs replaced with placeholders |
| `CLI_RESOLUTION` | CLI executable path discovery |
| `CLI_EXECUTION` | Full command with arguments, process lifecycle |
| `CLI_RESPONSE` | AI response content and length |
| `TOKEN_RESTORATION` | Placeholder replacement with original tokens |
| `PASTE_BACK` | Text replacement via AX or clipboard paste |

Use **Clear** to reset the log and **Copy All** to copy the full log to clipboard.

## Accessibility Permission

GhostEdit uses macOS Accessibility APIs to read/replace selected text directly and to send `Cmd+C`/`Cmd+V` as a fallback. Grant permission at:

- System Settings > Privacy & Security > Accessibility

## Testing

Run the full test+coverage gate:

```bash
./scripts/run_tests_with_coverage.sh
```

This gate enforces:
- Unit tests must pass.
- 100% line coverage on all core source files.

The same gate is wired into:
- `.githooks/pre-commit`
- `.githooks/pre-push`

Enable repo hooks locally:

```bash
git config core.hooksPath .githooks
```

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

## Privacy

- No accounts, no telemetry, no data collection.
- Text is processed locally through your own AI CLI nothing is sent to GhostEdit servers (there are none).
- This repo does not store local user prompt/config files from `~/.ghostedit`.

Before pushing, verify no local secrets were added:

```bash
rg -n "(api[_-]?key|token|secret|password|PRIVATE KEY)" .
```

## License

MIT
