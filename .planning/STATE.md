# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-26)

**Core value:** Instant, zero-latency grammar correction that works everywhere on macOS — local fixes handle 90% of cases without waiting for an LLM.
**Current focus:** Phase 2 — Text Selection Fixes

## Current Position

Phase: 2 of 3 (Text Selection Fixes)
Plan: 0 of ? in current phase
Status: Phase 1 complete, Phase 2 not yet planned
Last activity: 2026-02-27 — Phase 1 complete with additional fixes, context exhausted before Phase 2 planning

Progress: [███░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 1 (01-01)
- Average duration: ~4 min
- Total execution time: ~4 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-quick-fix-ux | 1 complete | ~4 min | ~4 min |
| 02-text-selection-fixes | 0 | — | — |

**Recent Trend:**
- Last 5 plans: 01-01
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Before/after diff for quick fix preview (not summary text): user wants to see exactly what changed
- Cursor-line-only for Notes: minimal scope — fix just the line under cursor, not surrounding text
- All incompatible apps get end-of-text cursor: consistent behavior across all AX-limited apps
- Full comparison table in settings: users must understand local vs LLM trade-offs to make informed choices
- 01-01: Use provider="Local", model="Harper" sentinel strings for local fix history entries — no schema changes
- 01-01: applyRuleBasedFixes returns String? so caller receives fixed text without re-querying AX
- 01-01: Popup positions above live feedback widget when visible, falls back to AX element bounds
- applyAllFixes returns (original, fixed)? tuple for live feedback path wiring
- pendingDiffOriginalText carries original text through async LLM flow for diff popup
- Foundation Model refusal detected by prefix matching + length check, falls back to Harper
- diffPreviewDuration stored as Int (seconds) in AppConfig with range 1-30

### Pending Todos

None yet.

### Blockers/Concerns

- Apple Intelligence on-device model refuses grammar correction prompts — mitigated with refusal detection + fallback to Harper+NSSpellChecker

## Session Continuity

Last session: 2026-02-27
Stopped at: Phase 1 complete, Phase 2 planning needed
Resume file: .planning/phases/01-quick-fix-ux/.continue-here.md
