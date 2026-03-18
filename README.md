<p align="center">
  <img src="assets/AppIcon1024.png" width="128" height="128" alt="GhostEdit" style="border-radius: 22px;">
</p>

<h1 align="center">GhostEdit</h1>

<p align="center">
  <strong>Fix your writing anywhere. No cloud required.</strong>
</p>

<p align="center">
  <a href="https://github.com/nareshnavinash/ghostedit-electron/releases/latest"><img src="https://img.shields.io/github/v/release/nareshnavinash/ghostedit-electron?color=22c55e&label=version" alt="Version"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue" alt="Platform">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/nareshnavinash/ghostedit-electron" alt="License"></a>
</p>

<p align="center">Cross-platform AI text correction from the menu bar</p>

---

### Why GhostEdit?

| | **GhostEdit** | Grammarly | LanguageTool | Apple Writing Tools |
|---|---|---|---|---|
| Works in any app | **Yes** (system-wide) | Browser + select apps | Browser + select apps | Yes |
| Offline mode | **Yes** (built-in T5 model) | No | Server only | Yes |
| Multi-provider AI | **Claude, GPT, Gemini, local** | Grammarly AI only | LanguageTool only | Apple AI only |
| Open source | **MIT** | No | LGPL | No |
| Price | **Free** | $12/mo | $5/mo (premium) | Free (Apple only) |

### Key Features

- **Works in every app** -- System-wide hotkey correction, not a browser extension
- **Offline-first AI** -- Built-in T5 grammar model runs on-device, no API keys needed
- **Multi-provider** -- Switch between local AI, Claude, GPT, or Gemini in one click
- **Real-time monitoring** -- Traffic light indicator shows writing quality as you type
- **Developer-friendly** -- Preserves code, URLs, @mentions, :emoji:, and file paths
- **13 languages + tone presets** -- Auto-detect language, choose from 5 writing styles

### Quick Start

1. **Download** the latest release from [GitHub Releases](https://github.com/nareshnavinash/ghostedit-electron/releases/latest)
2. **Open** GhostEdit -- it lives in your menu bar
3. **Select text** anywhere and press `Cmd+Shift+E` (Mac) or `Ctrl+Shift+E` (Win/Linux)

<!-- Add screenshot/GIF here: place a demo GIF or screenshot at assets/demo.gif and uncomment the line below -->
<!-- <p align="center"><img src="assets/demo.gif" width="600" alt="GhostEdit demo"></p> -->

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [AI Providers](#ai-providers)
- [Dictionary Engine](#dictionary-engine)
- [Architecture](#architecture)
- [Development](#development)
- [Testing](#testing)
- [Building & Packaging](#building--packaging)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Global hotkey** — Press `Cmd+Shift+E` (Mac) or `Ctrl+Shift+E` (Win/Linux) from any app
- **Offline-first** — Built-in T5 grammar model runs entirely on-device, no API keys needed
- **Cloud providers** — Claude, Codex (OpenAI), and Gemini via their CLI tools
- **Dictionary pre-pass** — Harper.js (grammar) + nspell (spelling) fix obvious errors before the AI sees the text, making corrections faster and cheaper
- **Dictionary polish** — Same engine runs again on model output to catch any remaining issues
- **Diff preview** — Side-by-side streaming diff before accepting changes (Tab to accept, Esc to cancel)
- **Token preservation** — URLs, @mentions, `:emoji:`, \`code\`, email addresses, and file paths are never modified
- **Tone presets** — Default, Casual, Professional, Academic, and Slack styles
- **13 languages** — Auto-detect or specify: English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Russian, Arabic, Hindi
- **Correction history** — Browse, search, and review past corrections
- **Correction cache** — Identical inputs skip the AI entirely
- **GPU acceleration** — DirectML (Windows), CUDA (Linux), WebGPU (macOS) for fast local inference
- **4 model variants** — Q4F16 (210 MB, bundled), INT8, FP16, FP32 (downloadable)
- **System tray** — Runs silently in the menu bar with no dock icon (macOS)

---

## Requirements

- **Node.js** >= 18
- **npm** >= 9
- **Operating System**: macOS 12+, Windows 10+, or Linux (x64/arm64)
- **Accessibility permissions** (macOS): Required for keyboard simulation — System Settings > Privacy & Security > Accessibility > enable GhostEdit

### Optional (for cloud providers)

| Provider | CLI Tool | Install |
|----------|----------|---------|
| Claude | `claude` | [claude.ai/cli](https://claude.ai/cli) |
| Codex | `codex` | `npm install -g @openai/codex` |
| Gemini | `gemini` | [ai.google.dev/gemini-api/docs/cli](https://ai.google.dev/gemini-api/docs/cli) |

Cloud providers are **not required** — the built-in local model works offline with zero setup.

---

## Installation

### Clone and install dependencies

```bash
git clone https://github.com/nareshnavinash/ghostedit-electron.git
cd ghostedit-electron
npm install
```

### Download the bundled model

The Q4F16 model variant (~210 MB) is bundled for offline use:

```bash
npm run download-model
```

This downloads the T5 grammar correction model to `resources/models/` for packaging.

---

## Quick Start

```bash
# Start the app in development mode
npm start
```

On first launch, a 3-step onboarding wizard will guide you through:

1. **Choose a provider** — Local (offline) or a cloud CLI
2. **Set the hotkey** — Default is `Cmd+Shift+E` / `Ctrl+Shift+E`
3. **Grant permissions** — On macOS, allow Accessibility access when prompted

After setup:

1. Select text in any application
2. Press the hotkey
3. A HUD overlay shows "Working..."
4. The corrected text replaces your selection (or appears in a diff preview)

---

## Usage

### Basic correction

1. **Select text** in any application (editor, browser, Slack, email, etc.)
2. **Press the hotkey** (`Cmd+Shift+E` by default)
3. GhostEdit captures the selection, corrects it, and pastes the result back

### Diff preview mode

When **Show diff preview** is enabled (default):

1. A preview window opens showing original vs. corrected text side-by-side
2. Insertions are highlighted in green, deletions in red
3. Press **Tab** to accept, **Escape** to cancel, **R** to regenerate

### Clipboard-only mode

When enabled, corrected text is copied to clipboard instead of being pasted back. Useful when paste simulation doesn't work in a specific app.

### System tray menu

Right-click (or click on macOS) the tray icon to access:

- **Correct Selected Text** — Trigger correction manually
- **Settings...** — Open the configuration window
- **History...** — Browse past corrections
- **Quit GhostEdit** — Exit the app

---

## Configuration

All settings are stored in `~/.ghostedit/config.json` and editable through the Settings window.

### Settings tabs

**General** — Provider, model, CLI path, language, tone, timeout

**Hotkey** — Record a custom global keyboard shortcut

**Behavior** — Toggle features:

| Setting | Description | Default |
|---------|-------------|---------|
| Fast correction mode | Greedy decoding for local model (faster, slight quality trade-off) | On |
| Clipboard-only mode | Copy to clipboard instead of pasting back | Off |
| Show diff preview | Side-by-side preview before applying | On |
| Sound feedback | Play sound on completion | On |
| Notify on success | System notification on correction | Off |
| Developer mode | Show inference device info in tray and settings | Off |
| History limit | Max stored corrections | 50 |

### Tone presets

| Preset | Style |
|--------|-------|
| Default | Standard grammar/spelling correction |
| Casual | Friendly, conversational, keeps contractions |
| Professional | Polished business communication |
| Academic | Formal vocabulary, precise structure |
| Slack | Concise, upbeat, preserves emoji and abbreviations |

### Custom system prompt

Create `~/.ghostedit/prompt.txt` to override the default system prompt. The file is read on each correction.

### Config file locations

| File | Purpose |
|------|---------|
| `~/.ghostedit/config.json` | Application settings |
| `~/.ghostedit/history.json` | Correction history |
| `~/.ghostedit/prompt.txt` | Custom system prompt (optional) |
| `~/.ghostedit/models/` | Downloaded model variants |
| `~/.ghostedit/device-cache.json` | Cached GPU/CPU detection result |

---

## AI Providers

### Local model (default)

The built-in model is [Xenova/t5-base-grammar-correction](https://huggingface.co/Xenova/t5-base-grammar-correction), a T5 model fine-tuned for grammar correction, running via ONNX Runtime through `@huggingface/transformers`.

**Model variants** (downloadable from Settings):

| Variant | Size | Quality | Speed |
|---------|------|---------|-------|
| Q4F16 | 210 MB | Good | Fastest |
| INT8 | 250 MB | Better | Fast |
| FP16 | 496 MB | High | Moderate |
| FP32 | 963 MB | Best | Slowest |

Q4F16 is bundled with the app. Other variants can be downloaded from the Settings window.

**GPU acceleration** is automatic:

| Platform | Primary Device | Fallback |
|----------|---------------|----------|
| macOS (Apple Silicon) | WebGPU (Metal) | WASM (CPU) |
| Windows (any GPU) | DirectML | WebGPU / WASM |
| Linux x64 (NVIDIA) | CUDA | WebGPU / WASM |
| Linux arm64 | WebGPU | WASM (CPU) |

### Cloud providers

Cloud providers use their respective CLI tools, spawned as subprocesses. You must install and authenticate the CLI separately.

**Claude**
```bash
# Install
# Visit https://claude.ai/cli

# Authenticate
claude auth login

# GhostEdit auto-detects the CLI, or set the path in Settings
```

**Codex (OpenAI)**
```bash
npm install -g @openai/codex
codex auth
```

**Gemini**
```bash
# Install from https://ai.google.dev/gemini-api/docs/cli
gemini auth
```

---

## Dictionary Engine

GhostEdit includes a two-layer dictionary engine that mirrors the approach from the companion macOS-native app:

### How it works

1. **Harper.js** (primary) — Rust-powered grammar checker compiled to WASM. Catches spelling, grammar, capitalization, and style issues with suggestions.

2. **nspell** (secondary) — JavaScript port of Hunspell with a full English dictionary. Fills non-overlapping gaps that Harper misses.

3. **Merge strategy** — All Harper issues are kept. nspell issues are added only if they don't overlap with any Harper issue. Proper nouns (capitalized mid-sentence) and acronyms (2+ uppercase letters) are filtered out.

4. **Iterative passes** — The engine runs up to 3 passes. Fixing one error can reveal another (e.g., fixing punctuation may expose a grammar error). Stops early when no more changes are found.

### Where it runs in the pipeline

```
Selected text
  -> Token protection (URLs, @mentions, code, emoji)
  -> Dictionary pre-pass (fix obvious errors)     <-- HERE
  -> Cache lookup
  -> AI model (local T5 or cloud CLI)
  -> Token restoration
  -> Dictionary polish (cleanup model output)      <-- AND HERE
  -> Paste back
```

The pre-pass means most simple typos ("teh" -> "the") never reach the AI model, making corrections faster and reducing API costs for cloud providers.

---

## Architecture

```
+-----------------------------------------------------------+
|                   Electron Main Process                     |
|                                                             |
|  Global Hotkey --> Clipboard Capture --> Token Protection    |
|       |                                                     |
|       v                                                     |
|  Dictionary Pre-pass (Harper + nspell, up to 3 passes)      |
|       |                                                     |
|       v                                                     |
|  Cache Lookup --[hit]--> Skip AI                            |
|       |                                                     |
|       v [miss]                                              |
|  Correction Dispatcher                                      |
|    +-- CLI Runner (claude/codex/gemini subprocess)          |
|    +-- Local Model Runner (transformers.js + ONNX)          |
|    +-- Inference Window (WebGPU/WASM in hidden renderer)    |
|       |                                                     |
|       v                                                     |
|  Token Restoration --> Dictionary Polish --> Paste Back      |
|       |                                                     |
|       v                                                     |
|  History Store --> Correction Cache                          |
|                                                             |
|  System Tray | IPC Handlers | Device Selector               |
+-----------------------------------------------------------+
                          | IPC
+-----------------------------------------------------------+
|                  Renderer Process (React)                    |
|                                                             |
|  Settings | History | HUD Overlay | Streaming Preview        |
|           | Onboarding Wizard | Inference Worker             |
+-----------------------------------------------------------+
```

### Key design decisions

- **Tray-only app** — No dock icon on macOS (`LSUIElement: true`). Runs silently in the menu bar.
- **Context isolation** — Renderer processes are sandboxed. All main/renderer communication goes through a secure preload bridge.
- **Graceful degradation** — If Harper fails to load (WASM issue), nspell still works. If both fail, the AI model handles everything. If the inference window crashes, the main process pipeline takes over.
- **Fire-and-forget pre-warming** — Model, dictionary checkers, and keyboard simulator are loaded in parallel at startup without blocking the UI.
- **Correction cache** — Keyed on `(text, provider, model, tone, language)`. Invalidated on any config change.

---

## Development

### Start in development mode

```bash
npm start
```

This launches Electron with Vite HMR — changes to renderer code are hot-reloaded instantly. Main process changes require a restart.

### Type checking

```bash
npx tsc --noEmit
```

### Linting

```bash
npm run lint
```

### Environment

The project uses:

- **TypeScript 5.7** with strict mode
- **Vite 6** for building main, preload, and renderer
- **React 19** for the UI
- **Tailwind CSS 3** with a custom dark theme
- **Zustand 5** for renderer state management
- **Vitest 4** for testing

---

## Testing

```bash
# Run all tests
npm test

# Watch mode
npm run test:watch

# Run a specific test file
npx vitest run src/main/dictionary-checker.test.ts

# Run with verbose output
npx vitest run --reporter=verbose
```

### Test structure

| File | Type | Tests | Covers |
|------|------|-------|--------|
| `dictionary-checker.test.ts` | Unit | 50 | Harper/nspell extraction, merge, filtering, fix application, initialization |
| `dictionary-checker.integration.test.ts` | Integration | 24 | End-to-end with real Harper WASM and nspell Hunspell |
| `local-model-runner.test.ts` | Unit | 22 | Pipeline loading, device routing, streaming, variant switching |
| `device-selector.test.ts` | Unit | 12 | Platform detection, disk caching, DirectML/CUDA probing |
| `correction-dispatcher.test.ts` | Unit | — | Provider routing logic |
| `correction-cache.test.ts` | Unit | — | Cache hit/miss/invalidation |
| `ipc-handlers.test.ts` | Unit | — | IPC handler registration and behavior |
| `cli-runner.test.ts` | Unit | — | CLI subprocess spawning and error handling |

Current: **161 tests, all passing**.

---

## Building & Packaging

### Package (unsigned)

```bash
npm run package
```

Creates an unpacked app in `out/`.

### Build installers

```bash
npm run make
```

Produces platform-specific installers:

| Platform | Format | Output |
|----------|--------|--------|
| macOS | DMG | `out/make/*.dmg` |
| Windows | Squirrel | `out/make/squirrel.windows/` |
| Linux | ZIP | `out/make/zip/linux-x64/` |

### What gets bundled

- The Electron app (ASAR-packed)
- Bundled Q4F16 model variant (`resources/models/`)
- All production dependencies
- App icon (`assets/icon.svg`)

---

## Project Structure

```
src/
  main/                          # Electron main process
    index.ts                     # App lifecycle, correction pipeline, window management
    config-manager.ts            # Config persistence (~/.ghostedit/)
    correction-dispatcher.ts     # Routes corrections to CLI or local model
    cli-runner.ts                # Spawns CLI subprocesses
    local-model-runner.ts        # Local T5 model via transformers.js
    dictionary-checker.ts        # Harper.js + nspell spell/grammar checking
    clipboard-manager.ts         # Cmd+C/V simulation via nut.js
    token-preservation.ts        # Protects URLs, @mentions, code, emoji
    correction-cache.ts          # In-memory correction cache
    history-store.ts             # Persists correction history to JSON
    tray-manager.ts              # System tray icon and context menu
    inference-window.ts          # Hidden BrowserWindow for GPU inference
    device-selector.ts           # GPU/CPU detection and caching
    global-shortcuts.ts          # Global hotkey registration
    ipc-handlers.ts              # IPC event handlers
    cli-arguments.ts             # CLI path resolution
    error-messages.ts            # User-friendly error messages

  renderer/                      # React UI
    App.tsx                      # Root component (routes by window type)
    main.tsx                     # React entry point
    windows/
      Settings.tsx               # Configuration UI
      History.tsx                # Correction history browser
      HudOverlay.tsx             # Transparent status overlay
      StreamingPreview.tsx       # Real-time diff preview
    components/
      Welcome.tsx                # Onboarding wizard
      DiffView.tsx               # Side-by-side diff viewer
      HotkeyInput.tsx            # Hotkey recording input
      ProviderSelector.tsx       # Provider selection buttons
      ModelSelector.tsx          # Model dropdown
    inference-worker.ts          # Web worker for model inference

  preload/
    index.ts                     # Secure IPC bridge (contextBridge)

  shared/
    types.ts                     # TypeScript interfaces and IPC channels
    constants.ts                 # Providers, models, languages, defaults

assets/
  icon.svg                       # App icon

resources/
  models/                        # Bundled T5 model (Q4F16 variant)

scripts/
  download-model.mjs             # Model download script
```

---

## Troubleshooting

### "No text was captured"

- Make sure text is selected before pressing the hotkey
- On macOS, grant Accessibility permission: System Settings > Privacy & Security > Accessibility > enable GhostEdit
- Try clipboard-only mode if paste simulation fails in a specific app

### "CLI: Not found"

- Install the CLI tool for your chosen provider (see [AI Providers](#ai-providers))
- Or set the CLI path manually in Settings > General

### "Authentication required"

- Run the auth command for your provider:
  - Claude: `claude auth login`
  - Codex: `codex auth`
  - Gemini: `gemini auth`

### Local model is slow

- Switch to the Q4F16 variant (smallest, fastest) in Settings
- Enable "Fast correction mode" in Behavior tab
- On Windows/Linux, ensure GPU drivers are up to date for DirectML/CUDA acceleration
- Check the inference device in Settings with Developer Mode enabled

### Corrections take too long

- Increase the timeout in Settings > General
- Switch to a faster model (e.g., `haiku` for Claude, `o4-mini` for Codex)
- Use the local model for instant offline corrections

### Hotkey doesn't work

- Check for conflicts with other apps using the same shortcut
- Change the hotkey in Settings > Hotkey tab
- On macOS, ensure the app has Accessibility permissions

### Model download fails

- Check your internet connection
- Try running `npm run download-model` from the terminal for detailed error output
- Models are downloaded from HuggingFace — ensure `huggingface.co` is accessible

---

## License

See [LICENSE](LICENSE) for details.
