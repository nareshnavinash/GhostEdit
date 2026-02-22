# GrammarFixer

GrammarFixer is a native macOS menu bar app that fixes selected text in any app using the local `claude` CLI.

## Features

- Global hotkey (`Command + E` by default)
- Works in background (no Dock icon)
- Configurable prompt in `~/.grammarfixer/prompt.txt`
- Configurable Claude model in **Settings...**
- Default model is **haiku**
- Menu bar state indicator:
  - `ⓖ` idle
  - `🤓` processing

## Directory Structure

```text
GrammarFixer/
├── .github/workflows/release.yml
├── .gitignore
├── project.yml
├── scripts/build_release.sh
├── scripts/notarize_release.sh
└── GrammarFixer/
    ├── Info.plist
    ├── Assets.xcassets/
    └── Sources/
        ├── AppDelegate.swift
        ├── ClipboardManager.swift
        ├── ConfigManager.swift
        ├── HotkeyManager.swift
        ├── ShellRunner.swift
        └── main.swift
```

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
open GrammarFixer.xcodeproj
```

4. Set your signing team and run.

## First Launch Files

GrammarFixer creates:

- `~/.grammarfixer/prompt.txt`
- `~/.grammarfixer/config.json`

Default `config.json`:

```json
{
  "claudePath": "",
  "model": "haiku",
  "hotkeyKeyCode": 14,
  "hotkeyModifiers": 256,
  "timeoutSeconds": 30
}
```

Notes:
- `claudePath` can be left empty if auto-discovery works.
- If auto-discovery fails, set an absolute path (for example: `/opt/homebrew/bin/claude`).

## Settings

Use the menu item **Settings...** to choose model:

- Haiku (default)
- Sonnet
- Opus
- Custom model name

## Accessibility Permission

GrammarFixer sends `Cmd+C` and `Cmd+V` programmatically. Grant permission at:

- System Settings > Privacy & Security > Accessibility

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

- `build/release/GrammarFixer-macOS.zip`
- `build/release/GrammarFixer-macOS.dmg`

For true out-of-the-box install on other Macs (no Gatekeeper warning), notarize the DMG:

```bash
NOTARY_PROFILE="your-notary-profile" ./scripts/notarize_release.sh build/release/GrammarFixer-macOS.dmg
```

`NOTARY_PROFILE` is a keychain profile created with Apple `notarytool`.

## GitHub Publishing

A workflow is included at `.github/workflows/release.yml`.

- Push a tag like `v1.0.0`
- Workflow builds and uploads `.zip` and `.dmg` to the GitHub Release
- For notarized releases, add signing/notary steps and secrets to the workflow

## Privacy and Repo Safety

This repo does not store local user prompt/config files from `~/.grammarfixer`.

Before pushing, verify no local secrets were added:

```bash
rg -n "(api[_-]?key|token|secret|password|PRIVATE KEY)" .
```
