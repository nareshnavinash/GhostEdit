# Roadmap: GhostEdit v7.0.0

## Overview

Three phases deliver the v7.0.0 milestone: fix the local quick fix experience (preview and undo), fix text selection bugs (Notes app scope and incompatible-app cursor placement), then surface what was built through settings transparency and an updated README. Each phase delivers one coherent, verifiable capability.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Quick Fix UX** - Diff preview after cmd+E and working undo for local fixes (completed 2026-02-26)
- [ ] **Phase 2: Text Selection Fixes** - Notes cursor-line scope and end-of-field cursor for incompatible apps
- [ ] **Phase 3: Transparency** - Settings comparison table, engine details, and SEO-optimized README

## Phase Details

### Phase 1: Quick Fix UX
**Goal**: Users get immediate visual feedback and reversibility when using the local quick fix (cmd+E)
**Depends on**: Nothing (first phase)
**Requirements**: QFX-01, QFX-02
**Success Criteria** (what must be TRUE):
  1. After pressing cmd+E, a before/after diff popup appears next to the floating widget and auto-dismisses after 3 seconds
  2. The diff popup shows the exact text that changed (not a summary)
  3. Selecting "Undo Last Correction" from the menu bar reverses a cmd+E local fix in the active text field
**Plans:** 1/1 plans complete
- [ ] 01-01-PLAN.md — Diff preview popup + undo history recording for local quick fix

### Phase 2: Text Selection Fixes
**Goal**: Text selection scope and cursor placement are correct across Notes and all incompatible apps
**Depends on**: Phase 1
**Requirements**: SEL-01, SEL-02
**Success Criteria** (what must be TRUE):
  1. In Notes app, pressing cmd+E with the cursor inside a paragraph fixes only that line's text, not the full page
  2. In Slack and other incompatible apps, the cursor is positioned at the end of the corrected text after cmd+E (not the beginning)
  3. The cursor behavior is consistent whether correction made a change or not
**Plans**: TBD

### Phase 3: Transparency
**Goal**: Users can understand what each correction mode does (in settings and in the README)
**Depends on**: Phase 2
**Requirements**: SET-01, SET-02, DOC-01
**Success Criteria** (what must be TRUE):
  1. The Settings page contains a comparison table showing what cmd+E (local) vs cmd+shift+E (LLM) fixes
  2. On macOS 26+, Settings shows a confirmation that Apple Intelligence is active as the local fix engine
  3. On macOS 13-25, Settings shows that Harper + NSSpellChecker is active
  4. The README explains the local fix and Apple Intelligence value proposition in plain language that non-technical users can act on
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Quick Fix UX | 1/1 | Complete   | 2026-02-26 |
| 2. Text Selection Fixes | 0/? | Not started | - |
| 3. Transparency | 0/? | Not started | - |
