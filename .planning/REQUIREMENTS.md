# Requirements: GhostEdit v7.0.0

**Defined:** 2026-02-26
**Core Value:** Instant, zero-latency grammar correction that works everywhere on macOS — local fixes handle 90% of cases without waiting for an LLM.

## v1 Requirements

### Quick Fix UX

- [x] **QFX-01**: After cmd+E local fix, a before/after diff preview appears next to the floating widget for 3 seconds then auto-dismisses
- [x] **QFX-02**: Undo last correction menu item works correctly for local quick fix (cmd+E) corrections

### Text Selection

- [ ] **SEL-01**: In Notes app, cmd+E fixes only the line where the cursor is positioned (not the entire page)
- [ ] **SEL-02**: In all incompatible apps (Slack, etc.), cursor moves to end of text field after correction (not start)

### Settings

- [ ] **SET-01**: Settings page shows full comparison table: local fixes (cmd+E) vs LLM fixes (cmd+shift+E) with capabilities listed
- [ ] **SET-02**: Settings page displays Apple Intelligence availability for macOS 26+ and local fix engine details (Harper + NSSpellChecker for older macOS)

### Documentation

- [ ] **DOC-01**: README updated with SEO-optimized showcase of local fix + Apple Intelligence value, targeting both technical and non-technical audiences

## v2 Requirements

### Advanced Undo

- **UNDO-01**: Multi-level undo stack (10 levels) for both local and LLM corrections
- **UNDO-02**: Cmd+Z integration for sequential undo

### Text Selection Enhancements

- **SEL-03**: Paragraph-level selection mode as alternative to line-only
- **SEL-04**: Multi-line selection awareness (fix only selected lines)

## Out of Scope

| Feature | Reason |
|---------|--------|
| AppDelegate refactoring (split into files) | Technical debt, not user-facing — defer to separate cleanup milestone |
| Live feedback mode improvements | Already working, not part of this milestone |
| New LLM provider integrations | Existing 3 providers sufficient |
| iOS/mobile port | Desktop-only product |
| Cloud API (HTTP) instead of CLI | Architectural decision to use CLI tools |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| QFX-01 | Phase 1 | Complete |
| QFX-02 | Phase 1 | Complete |
| SEL-01 | Phase 2 | Pending |
| SEL-02 | Phase 2 | Pending |
| SET-01 | Phase 3 | Pending |
| SET-02 | Phase 3 | Pending |
| DOC-01 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0

---
*Requirements defined: 2026-02-26*
*Last updated: 2026-02-26 after roadmap creation*
