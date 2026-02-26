---
phase: 01-quick-fix-ux
plan: 01
subsystem: ui
tags: [swift, appkit, diff, history, undo, nspanel, axuielement]

# Dependency graph
requires: []
provides:
  - QuickFixDiffPopupController class with animated before/after character-level diff popup
  - recordLocalFixHistoryEntry() for capturing local fix history with provider "Local", model "Harper"
  - Undo support for cmd+E local fixes via existing undoLastCorrectionAction()
  - widgetFrame accessor on LiveFeedbackController for popup positioning
affects:
  - 01-quick-fix-ux
  - future history/undo plans

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSPanel floating popup with NSVisualEffectView (hudWindow material) for non-blocking UI
    - DiffSupport.charDiff() with NSAttributedString for green/red character-level diff rendering
    - DispatchWorkItem for cancellable auto-dismiss timers
    - @discardableResult on methods that conditionally return values

key-files:
  created: []
  modified:
    - GhostEdit/Sources/AppDelegate.swift

key-decisions:
  - "Use provider='Local', model='Harper' as sentinel strings for local fix history entries (no schema change)"
  - "Return String? from applyRuleBasedFixes so caller receives fixed text without re-querying AX"
  - "Position popup above live feedback widget when visible, otherwise below the AX text element"
  - "Auto-dismiss after 3 seconds via cancellable DispatchWorkItem"
  - "startProcessingIndicator() dismisses diff popup to prevent stacking with LLM flow"

patterns-established:
  - "Local fix history: sentinel provider/model strings in CorrectionHistoryEntry without schema changes"
  - "Popup positioning: prefer widgetFrame if widget visible, fall back to AX element bounds"

requirements-completed: [QFX-01, QFX-02]

# Metrics
duration: 4min
completed: 2026-02-26
---

# Phase 1 Plan 01: Quick Fix Diff Preview and Undo Summary

**Floating character-level diff popup (green/red) after cmd+E plus undo support via CorrectionHistoryStore sentinel entries**

## Performance

- **Duration:** ~4 min (automated tasks) + human verify pending
- **Started:** 2026-02-26T15:16:06Z
- **Completed:** 2026-02-26T15:20:00Z (Tasks 1-2 complete, Task 3 pending human-verify)
- **Tasks:** 2 of 3 automated (Task 3 is human-verify checkpoint)
- **Files modified:** 1

## Accomplishments

- `recordLocalFixHistoryEntry(original:fixed:)` added to AppDelegate, recording local fixes with provider "Local" / model "Harper" — `undoLastCorrectionAction()` now finds these automatically via `historyStore.lastSuccessfulEntry()`
- `applyRuleBasedFixes` return type changed from `Void` to `String?` returning the fixed text when fixCount > 0, enabling the caller to capture the result
- `QuickFixDiffPopupController` class added with animated show/dismiss, character-level diff rendering using `DiffSupport.charDiff()`, green insertions with underline, red deletions with strikethrough, auto-dismiss after 3 seconds, click-to-dismiss
- `showQuickFixDiffPopup(original:fixed:near:)` wired into all three fix paths: Foundation Model success, Foundation Model fallback to rule-based, and direct rule-based (macOS <26)
- `startProcessingIndicator()` dismisses any active diff popup to prevent stacking when LLM flow starts
- `widgetFrame` accessor added to `LiveFeedbackController` for popup positioning above the live feedback widget
- All 554 tests pass (no guarded files modified)

## Task Commits

Each task was committed atomically:

1. **Task 1: Record local fix history entries and wire undo support** - `664d6a5` (feat)
2. **Task 2: Build QuickFixDiffPopupController and wire diff preview** - `50e2d0b` (feat)
3. **Task 3: Verify diff preview and undo in running app** - awaiting human-verify

## Files Created/Modified

- `/Users/nareshsekar/Desktop/Scripts/grammar/GrammarFixer/GhostEdit/Sources/AppDelegate.swift` — Added `recordLocalFixHistoryEntry`, `showQuickFixDiffPopup`, `QuickFixDiffPopupController` class; changed `applyRuleBasedFixes` return type; wired all three fix paths; added `widgetFrame` accessor; `startProcessingIndicator()` dismisses popup

## Decisions Made

- Used `provider: "Local"`, `model: "Harper"` as sentinel strings — no `CorrectionHistoryEntry` schema change needed, on-disk history.json remains compatible
- `applyRuleBasedFixes` returns `String?` (fixed text when fixCount > 0, nil when no changes) so caller receives fixed text without re-querying AX
- Popup positions above live feedback widget when visible, falls back to AX element bounds when widget is absent
- Auto-dismiss uses a cancellable `DispatchWorkItem` — cancelled when `show()` or `dismiss()` is called
- `startProcessingIndicator()` nilifies and dismisses popup to prevent stacked popups from cmd+E then cmd+shift+E

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — both automated tasks compiled and all 554 tests passed on first attempt.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Human verification of Task 3 pending (app installed at /Applications/GhostEdit.app, running)
- After human verifies: diff popup appearance, auto-dismiss, undo behavior, no-change case, LLM-dismisses-popup case
- Ready to proceed to next plan (01-02) once Task 3 is confirmed

---
*Phase: 01-quick-fix-ux*
*Completed: 2026-02-26*
