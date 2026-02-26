# GhostEdit — v7.0.0 Milestone

## What This Is

A macOS menu bar app that fixes grammar, spelling, and style in any text field system-wide. Two correction modes: **cmd+E** for instant local fixes (Harper + NSSpellChecker, or Apple Intelligence on macOS 26+) and **cmd+shift+E** for deep LLM-powered corrections (Claude/Gemini/Codex). Targets macOS 13.0+, built with AppKit and Swift 5.

## Core Value

Instant, zero-latency grammar correction that works everywhere on macOS — local fixes handle 90% of cases without waiting for an LLM.

## Requirements

### Validated

- ✓ System-wide hotkey correction via LLM (Claude/Gemini/Codex) — v1.0
- ✓ Streaming preview with character-level diff highlighting — v3.0
- ✓ Side-by-side diff preview (before/after) — v2.0
- ✓ Correction history with search, filter, and badges — v2.0
- ✓ Token preservation for URLs, emails, @mentions, code blocks, emojis — v1.0
- ✓ Multiple LLM providers with per-app profile overrides — v4.0
- ✓ On-device grammar/spelling via Harper (Rust) bridge — v6.0
- ✓ HUD overlay ghost widget with success/error animations — v3.0
- ✓ Tabbed settings (General/Hotkey/Behavior/Advanced) — v2.0
- ✓ Launch at login via ServiceManagement — v1.0
- ✓ Live feedback mode with real-time issue detection — v5.0
- ✓ Writing coach with tone presets — v5.0
- ✓ Dual hotkey: cmd+E (local) / cmd+shift+E (LLM) — v6.0
- ✓ Apple Intelligence support via FoundationModels (macOS 26+) — v6.0
- ✓ Draggable floating widget — v6.0

### Active

- [ ] Local quick fix preview: show before/after diff next to floating widget for 3 seconds after cmd+E
- [ ] Incompatible apps pointer fix: move cursor to end (not start) after correction for all incompatible apps
- [ ] Notes app cursor-line-only: fix only the line where cursor is positioned, not the entire page
- [ ] Undo for local quick fix: undo last correction menu item must work for cmd+E local fixes
- [ ] Settings page: full comparison table showing local fixes (cmd+E) vs LLM fixes (cmd+shift+E) with capabilities
- [ ] Settings page: display Apple Intelligence availability (macOS 26+) and local fix engine details
- [ ] README update: SEO-optimized showcase of local fix + Apple Intelligence value proposition for both technical and non-technical audiences

### Out of Scope

- Mobile app / iOS port — desktop-only product
- Cloud API integration (HTTP) — uses CLI tools by design for auth simplicity
- Multi-level undo stack — single undo is sufficient for this milestone
- Feature flags / A/B testing — not needed for single-user desktop app
- Real-time collaborative editing — not in scope

## Context

**Existing codebase:** ~9K lines across 33 source files. AppDelegate.swift is the monolithic orchestrator (~4,600 lines) containing all UI controllers. Support modules are pure-logic enums with 100% test coverage enforced on 26 files.

**Local fix engine:** On macOS 13-25, Harper (Rust via C FFI) handles grammar and NSSpellChecker handles spelling. On macOS 26+, Apple Intelligence via FoundationModels framework provides native on-device correction. The dual-hotkey system (cmd+E / cmd+shift+E) is already wired but not reflected in the UI/settings.

**Known issues:**
- Incompatible apps (Slack, etc.) move cursor to start of text field after correction — should move to end
- Notes app sends entire page content via accessibility API when no text is selected — should limit to cursor line
- Undo menu item doesn't work for local quick fix corrections (only works for LLM corrections)
- Settings page doesn't explain the local vs LLM distinction or show what each mode fixes
- No user-facing indication of Apple Intelligence availability on macOS 26+

**Key selling point:** Apple Intelligence powers the quick fix on macOS 26+. Most day-to-day corrections (spelling, grammar during Slack messages, emails) don't need an LLM — the local fix handles them instantly. LLM is there for deeper rewrites when needed.

## Constraints

- **Platform**: macOS 13.0+ — must work on pre-Apple Intelligence Macs too
- **UI Framework**: Programmatic AppKit only — no SwiftUI, no XIBs
- **Test Coverage**: 100% line coverage on all 26 guarded Support modules
- **Architecture**: Support modules are `enum` namespaces with `static` methods
- **Build**: Three-target architecture (GhostEditCore framework, GhostEdit app, GhostEditTests)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Before/after diff for preview (not summary text) | User wants to see exactly what changed, not just counts | — Pending |
| Cursor-line-only for Notes (not paragraph) | User wants minimal scope — fix just the line, not surrounding text | — Pending |
| All incompatible apps get end-of-text cursor (not just Slack) | Consistent behavior across all apps with AX limitations | — Pending |
| Full comparison table in settings (not simple toggle) | Users should understand what local vs LLM fixes and make informed choice | — Pending |
| Both audiences for README (technical + non-technical) | GitHub visitors are developers but product value appeals to everyone | — Pending |

---
*Last updated: 2026-02-26 after initialization*
