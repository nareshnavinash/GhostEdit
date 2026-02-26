# Phase 1: Quick Fix UX - Research

**Researched:** 2026-02-26
**Domain:** macOS AppKit — floating panels, diff display, undo state for local (on-device) grammar fixes
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QFX-01 | After cmd+E local fix, a before/after diff preview appears next to the floating widget for 3 seconds then auto-dismisses | `DiffSupport.charDiff()` + new `QuickFixDiffPopup` NSPanel (pattern: `HUDOverlayController` + `LiveFeedbackController.showPopover()`) |
| QFX-02 | Undo last correction menu item works correctly for local quick fix (cmd+E) corrections | `undoLastCorrectionAction()` already uses `historyStore.lastSuccessfulEntry()`. Gaps: local fix never calls `recordHistoryEntry()`, so there is nothing to undo. Fix: record entry from `handleLocalFixHotkey()` after each successful fix. |
</phase_requirements>

---

## Summary

Phase 1 requires two changes to `AppDelegate.swift`. First, `handleLocalFixHotkey()` must capture the original text before applying fixes, compute a character-level diff against the fixed text, and display that diff in a small floating NSPanel positioned next to the existing `widgetWindow` (or, if live feedback is not active, near the cursor's text field). The panel auto-dismisses after 3 seconds. Second, `handleLocalFixHotkey()` must record a `CorrectionHistoryEntry` so that the existing `undoLastCorrectionAction()` — which is already fully implemented and works via `historyStore.lastSuccessfulEntry()` — can actually find a local-fix entry to undo.

Both changes are self-contained within `AppDelegate.swift`. No new source files need to be created; only `AppDelegate.swift` needs modification. No guarded Support modules are changed, so the 100% coverage gate is not at risk. The diff popup reuses `DiffSupport.charDiff()` (already tested) and the NSPanel construction pattern from the existing `HUDOverlayController` and `LiveFeedbackController.showPopover()`.

**Primary recommendation:** Add `recordHistoryEntry()` call and a new `showQuickFixDiffPopup(original:fixed:near:)` call inside `handleLocalFixHotkey()` (after text is written via AX). The popup is a standalone borderless NSPanel — do not reuse or modify `HUDOverlayController`, which is used for the LLM correction path.

---

## Standard Stack

### Core
| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| `AppKit.NSPanel` | macOS 13+ | Borderless floating diff popup | Same pattern as existing `HUDOverlayController` and `LiveFeedbackController.widgetWindow` |
| `DiffSupport.charDiff(old:new:)` | (in-repo) | Compute character-level diff segments | Already tested; produces `[DiffSegment]` with `.equal`, `.insertion`, `.deletion` |
| `NSVisualEffectView` | macOS 13+ | Frosted-glass popup background | Used by `HUDOverlayController.buildPanel()` |
| `NSAttributedString` | macOS 13+ | Render colored diff text | Same approach as `DiffPreviewController.buildAttributedDiff()` |
| `DispatchWorkItem` + `DispatchQueue.main.asyncAfter` | Foundation | Auto-dismiss after 3 seconds | Same pattern as `HUDOverlayController.scheduleAutoDismissIfNeeded()` |
| `CorrectionHistoryStore.append()` | (in-repo) | Record local fix entry | Already used for LLM corrections in `recordHistoryEntry()` |
| `AccessibilityTextSupport` | (in-repo) | Read AX element position/size for popup placement | Same AX calls used in `LiveFeedbackController.positionWidget(near:)` |

### Supporting
| Library / API | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| `NSAnimationContext` | macOS 13+ | Fade-in/fade-out animations | Reuse existing animation pattern from `HUDOverlayController.show()` |
| `DiffSupport.changeSummary(segments:)` | (in-repo) | Optional count summary label | Use as subtitle if desired ("2 words fixed") |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New standalone NSPanel popup | Reuse `HUDOverlayController` | HUD is for LLM path; mixing state makes both harder to maintain. Keep separate. |
| `DiffSupport.charDiff` | `wordDiff` | `charDiff` is more precise for showing exact characters changed (requirement says "exact text that changed"). Use `charDiff`. |
| Inline colored `NSAttributedString` in popup | Custom `NSTextView` with drawing | Inline `NSAttributedString` in a non-editable `NSTextView` (or `NSTextField` for small text) is sufficient. Match the `DiffPreviewController` approach. |

---

## Architecture Patterns

### Recommended Project Structure

No new files needed. All changes go into `AppDelegate.swift`.

The new diff popup can be a lightweight private inner class `QuickFixDiffPopupController` (modeled on `HUDOverlayController`) defined at the bottom of `AppDelegate.swift`. AppDelegate holds a `private var quickFixDiffPopup: QuickFixDiffPopupController?`.

```
GhostEdit/Sources/
├── AppDelegate.swift          ← ALL Phase 1 changes here
│   ├── handleLocalFixHotkey() ← capture originalText, call popup + recordEntry
│   ├── QuickFixDiffPopupController  ← new private class (end of file)
│   └── (no changes to undoLastCorrectionAction — it already works once entry is recorded)
└── (no other files changed)
```

### Pattern 1: Capturing original text before local fix

`handleLocalFixHotkey()` already reads `currentText` from the AX element at line 666. This is the `originalText`. After applying fixes (lines 761–777), `nsText` holds the corrected string.

The original text and fixed text must be captured **before and after** applying AX writes, then passed to the popup and history recorder.

```swift
// Inside handleLocalFixHotkey() — AFTER fixes applied, BEFORE showHUD
let originalForUndo = currentText
let fixedText = nsText as String   // nsText built in applyRuleBasedFixes

if fixCount > 0 {
    recordLocalFixHistoryEntry(original: originalForUndo, fixed: fixedText)
    showQuickFixDiffPopup(original: originalForUndo, fixed: fixedText, near: element, pid: pid)
}
```

**Important:** `applyRuleBasedFixes` and `FoundationModelSupport` paths are separate. Both must be updated. The Foundation Model path sets `trimmed` directly — capture `currentText` before and `trimmed` after.

### Pattern 2: Recording a local fix history entry

`recordHistoryEntry()` currently requires a `CLIProvider` and model string, which are LLM-specific. Local fixes use Harper + NSSpellChecker, not a CLI provider.

**Approach A (preferred):** Create a dedicated `recordLocalFixHistoryEntry(original:fixed:fixCount:)` method that calls `historyStore.append()` with `provider: "Local"`, `model: "Harper"`, `durationMilliseconds: 0` (or measured), `succeeded: true`. This maps cleanly to the `CorrectionHistoryEntry` Codable structure without requiring schema changes.

```swift
private func recordLocalFixHistoryEntry(original: String, fixed: String) {
    let entry = CorrectionHistoryEntry(
        id: UUID(),
        timestamp: Date(),
        originalText: original,
        generatedText: fixed,
        provider: "Local",
        model: "Harper",
        durationMilliseconds: 0,
        succeeded: true
    )
    let limit = configManager.loadConfig().historyLimit
    try? historyStore.append(entry, limit: limit)
    refreshHistoryWindowIfVisible()
}
```

Once this entry is saved, `historyStore.lastSuccessfulEntry()` in `undoLastCorrectionAction()` will return it, and the undo paste path will correctly restore the `originalText`.

### Pattern 3: Floating diff popup (QFX-01)

Construct a borderless `NSPanel` (`.borderless`, `.nonactivatingPanel`) using the same recipe as `HUDOverlayController.buildPanel()`. Position it adjacent to `widgetWindow` if live feedback is active, otherwise near the focused AX element (use AX position + size conversion, same as `positionWidget(near:)`).

Panel sizing: Use a fixed-width popup (~280–320 px wide, auto-height up to ~120 px). Display the diff as an `NSAttributedString` in a non-editable `NSTextView`. Use green background + underline for insertions, red background + strikethrough for deletions, same as `DiffPreviewController.buildAttributedDiff()`.

**Auto-dismiss:** Schedule a `DispatchWorkItem` for 3.0 seconds (matching `LiveFeedbackSupport.cleanAutoDismissDelay`). Cancel the work item if the popup is closed early. Use `NSAnimationContext` fade-out (same as `HUDOverlayController.dismiss()`).

```swift
// Popup auto-dismiss (3 seconds per QFX-01)
let workItem = DispatchWorkItem { [weak self] in
    self?.dismissQuickFixDiffPopup()
}
dismissWorkItem = workItem
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
```

**Positioning near widget:** If `widgetWindow` is visible (live feedback active), position the popup immediately above the widget frame. If not, fall back to positioning below the focused text field (same AX query as `positionWidget(near:)`).

```swift
// Position next to live feedback widget if it exists
if let widgetFrame = liveFeedbackController?.widgetFrame {
    let popupX = widgetFrame.origin.x
    let popupY = widgetFrame.origin.y + widgetFrame.height + 4
    panel.setFrameOrigin(NSPoint(x: popupX, y: popupY))
} else {
    // Fall back: position near focused AX element
    // (same AX position+size query as positionWidget)
}
```

Note: `LiveFeedbackController.widgetWindow` is private. To expose the widget frame, either add a `var widgetFrame: NSRect? { widgetWindow?.frame }` accessor to `LiveFeedbackController`, or let `AppDelegate` hold a `lastWidgetFrame` property updated when live feedback positions the widget.

### Anti-Patterns to Avoid

- **Reusing `HUDOverlayController` for diff display:** The HUD is a centered ghost-icon overlay for LLM corrections. The diff popup is edge-anchored and text-based. They are different UX roles.
- **Modifying `CorrectionHistoryEntry` schema:** The struct is Codable and history.json is on disk. Do not add new fields. Use `provider: "Local"` and `model: "Harper"` as sentinel strings within the existing schema — the undo action just needs `originalText`.
- **Calling `processSelectedText()` for local fixes:** The local fix path (`handleLocalFixHotkey`) is entirely separate from the LLM path (`handleHotkeyTrigger` → `processSelectedText`). Do not mix them.
- **Blocking the main thread:** All AX calls in `handleLocalFixHotkey` run synchronously on the main thread already (consistent with existing code). The diff computation (`DiffSupport.charDiff`) is O(N*M) but input is a single text field — acceptable on main thread for typical inputs.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Diff computation | Custom diff algorithm | `DiffSupport.charDiff(old:new:)` | Myers diff already in repo, 100% tested |
| Colored diff rendering | Custom drawing | `NSAttributedString` with `.backgroundColor`, `.strikethroughStyle`, `.underlineStyle` | Same as `DiffPreviewController.buildAttributedDiff()` — already validated pattern |
| Popup fade animation | Custom CAAnimation | `NSAnimationContext.runAnimationGroup` | Same as `HUDOverlayController.show()`/`dismiss()` — already works |
| Auto-dismiss timer | NSTimer loop | `DispatchWorkItem` + `asyncAfter` | Same as `HUDOverlayController.scheduleAutoDismissIfNeeded()` — cancellable |

---

## Common Pitfalls

### Pitfall 1: Local fix never records history — undo silently fails
**What goes wrong:** User presses cmd+E, fixes are applied, then user opens menu and clicks "Undo Last Correction." `historyStore.lastSuccessfulEntry()` returns the most recent LLM entry (or nil), not the local fix. The wrong text gets pasted back.
**Why it happens:** `handleLocalFixHotkey()` calls `showHUD()` but never calls `recordHistoryEntry()` or any equivalent.
**How to avoid:** Always record the local fix entry before returning from `handleLocalFixHotkey()` when `fixCount > 0`.
**Warning signs:** "Undo Last Correction" restores LLM-corrected text instead of the pre-local-fix text.

### Pitfall 2: Foundation Model path (macOS 26+) bypasses fix recording
**What goes wrong:** On macOS 26+, `handleLocalFixHotkey()` branches into a `Task { @MainActor in ... }` async block that calls `FoundationModelSupport.correctText()`. The fix is applied but no history entry or popup is shown.
**Why it happens:** The async path (`if #available(macOS 26, *), FoundationModelSupport.isAvailable`) is a separate code path from `applyRuleBasedFixes`.
**How to avoid:** Both the Foundation Model success path and the `applyRuleBasedFixes` fallback must call `recordLocalFixHistoryEntry()` and `showQuickFixDiffPopup()`.
**Warning signs:** On macOS 26+, diff popup appears only sometimes (only when Foundation Models fail and fall back to rules).

### Pitfall 3: Popup positioned off-screen
**What goes wrong:** Popup appears outside visible screen bounds when text field is near an edge.
**Why it happens:** AX coordinates are in top-left screen space; Cocoa uses bottom-left. Naive conversion can push the popup off the screen bottom.
**How to avoid:** Add the same clamp logic as `positionWidget(near:)` — if computed Y < `screen.visibleFrame.minY`, flip to position above the text field. Clamp X to `[0, screen.visibleFrame.maxX - popupWidth]`.
**Warning signs:** Popup invisible despite no crash.

### Pitfall 4: Popup visible during LLM correction flow
**What goes wrong:** If the user presses cmd+E and then cmd+shift+E immediately, two overlapping popups appear.
**Why it happens:** `quickFixDiffPopup` is not dismissed when the LLM flow starts.
**How to avoid:** In `handleHotkeyTrigger()` (or `startProcessingIndicator()`), call `quickFixDiffPopup?.dismiss()` / `quickFixDiffPopup = nil`.
**Warning signs:** Stacked panels on screen.

### Pitfall 5: `widgetWindow` is private in `LiveFeedbackController` — can't position popup adjacent
**What goes wrong:** `AppDelegate.handleLocalFixHotkey()` cannot read `liveFeedbackController.widgetWindow?.frame` because `widgetWindow` is declared `private`.
**Why it happens:** Strict encapsulation in `LiveFeedbackController`.
**How to avoid:** Add a `var widgetFrame: NSRect? { widgetWindow?.frame }` computed property to `LiveFeedbackController`, or store the last-known widget origin as a published property. Alternatively, accept the fallback: if no widget frame is available, use the AX element bounds for positioning.

### Pitfall 6: `applyPerWordFixes` path returns `Bool` — original text is `currentText`, not `nsText`
**What goes wrong:** `applyRuleBasedFixes` applies per-word replacements via AX (not full-text replacement). In this case, `nsText` is the expected final text, but the actual written text is assembled word-by-word. The diff should be `currentText` → `nsText as String` regardless of which code path wrote the bytes.
**Why it happens:** Two code paths: full-text AX write (`kAXValueAttribute`) vs. per-word AX replacement (`kAXSelectedTextAttribute`). Both aim to produce `nsText`.
**How to avoid:** Compute the diff from `currentText` → `nsText as String` in both paths. Capture `originalText = currentText` before any modification, compute diff after building `nsText`, regardless of which write path succeeded.

---

## Code Examples

### QFX-01: Show diff popup after local fix

```swift
// Source: pattern from DiffPreviewController.buildAttributedDiff() + HUDOverlayController.buildPanel()

private func showQuickFixDiffPopup(
    original: String,
    fixed: String,
    near element: AXUIElement,
    pid: pid_t
) {
    let segments = DiffSupport.charDiff(old: original, new: fixed)
    // Only show if there are actual changes
    guard segments.contains(where: { $0.kind != .equal }) else { return }

    quickFixDiffPopup?.dismiss()

    let popup = QuickFixDiffPopupController()
    popup.show(segments: segments, near: element, widgetFrame: liveFeedbackController?.widgetFrame)
    quickFixDiffPopup = popup
}
```

### QFX-02: Record local fix history entry

```swift
// Source: pattern from recordHistoryEntry() in AppDelegate.swift ~line 2123

private func recordLocalFixHistoryEntry(original: String, fixed: String) {
    let entry = CorrectionHistoryEntry(
        id: UUID(),
        timestamp: Date(),
        originalText: original,
        generatedText: fixed,
        provider: "Local",
        model: "Harper",
        durationMilliseconds: 0,
        succeeded: true
    )
    let limit = configManager.loadConfig().historyLimit
    try? historyStore.append(entry, limit: limit)
    refreshHistoryWindowIfVisible()
}
```

### Popup panel construction (new private class)

```swift
// Source: pattern from HUDOverlayController.buildPanel() ~line 4689 and
//         DiffPreviewController.buildAttributedDiff() ~line 2415

final class QuickFixDiffPopupController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private static let autoDismissDelay: TimeInterval = 3.0
    private static let popupWidth: CGFloat = 300
    private static let popupMaxHeight: CGFloat = 120

    func show(segments: [DiffSegment], near element: AXUIElement, widgetFrame: NSRect?) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)

        let popup = buildPanel(segments: segments)
        positionPanel(popup, near: element, widgetFrame: widgetFrame)
        popup.alphaValue = 0
        popup.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            popup.animator().alphaValue = 1
        }
        self.panel = popup

        let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: workItem)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        })
    }

    private func buildPanel(segments: [DiffSegment]) -> NSPanel { /* ... */ }
    private func positionPanel(_ panel: NSPanel, near element: AXUIElement, widgetFrame: NSRect?) { /* ... */ }
}
```

### Diff text rendering (inside buildPanel)

```swift
// Source: DiffPreviewController.buildAttributedDiff() ~line 2415

let result = NSMutableAttributedString()
let font = NSFont.systemFont(ofSize: 12)
for segment in segments {
    let attrs: [NSAttributedString.Key: Any]
    switch segment.kind {
    case .equal:
        attrs = [.font: font, .foregroundColor: NSColor.labelColor]
    case .insertion:
        attrs = [
            .font: font,
            .foregroundColor: NSColor.systemGreen,
            .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    case .deletion:
        attrs = [
            .font: font,
            .foregroundColor: NSColor.systemRed,
            .backgroundColor: NSColor.systemRed.withAlphaComponent(0.15),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
    }
    result.append(NSAttributedString(string: segment.text, attributes: attrs))
}
```

### AX element position → popup origin (Cocoa coords)

```swift
// Source: LiveFeedbackController.positionWidget(near:) ~line 5407

var posValue: AnyObject?
var szValue: AnyObject?
AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &szValue)

var position = CGPoint.zero
var size = CGSize.zero
AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
AXValueGetValue(szValue as! AXValue, .cgSize, &size)

if let screen = NSScreen.main {
    let screenHeight = screen.frame.height
    // Convert from top-left to Cocoa bottom-left
    let fieldBottomY = screenHeight - (position.y + size.height)
    var popupY = fieldBottomY - popupHeight - 8
    if popupY < screen.visibleFrame.minY {
        popupY = screenHeight - position.y + 8  // above field
    }
    let popupX = position.x + size.width - popupWidth  // right-aligned with field
    let clampedX = max(screen.visibleFrame.minX, min(screen.visibleFrame.maxX - popupWidth, popupX))
    panel.setFrameOrigin(NSPoint(x: clampedX, y: max(0, popupY)))
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Local fix had no history recording | Must add `recordLocalFixHistoryEntry()` | Undo silently does nothing for local fixes until this is added |
| Diff popup only existed for LLM streaming path (`StreamingPreviewController`) | New per-hotkey quick popup for local fix | Must build new `QuickFixDiffPopupController` |
| `HUDOverlayState.successWithCount(Int)` counts chars (LLM chars, not fix count) | Local fix uses `showHUD(state: .successWithCount(fixCount))` — currently shows "N chars fixed" when it means N words fixed | Consider fixing the message text to say "N fixes" not "N chars"; but this is cosmetic, not required by Phase 1 |

**Deprecated/outdated:**
- Nothing deprecated in this phase. All APIs used (AppKit NSPanel, AX APIs, DiffSupport) are current on macOS 13+.

---

## Open Questions

1. **Where to position the popup when live feedback widget is not visible**
   - What we know: `positionWidget(near:)` already does this for live feedback. The element AX bounds are available.
   - What's unclear: Whether to match the exact widget position or use a slightly different anchor (e.g., beside the widget if visible, below text field if not).
   - Recommendation: Position above the widget if visible (popup appears directly above the 36×36 icon), otherwise use the "below text field" logic from `positionWidget`. This matches the "appears next to the floating widget" language in QFX-01.

2. **How to expose `widgetWindow.frame` from `LiveFeedbackController`**
   - What we know: `widgetWindow` is private. `AppDelegate` holds `liveFeedbackController` but cannot read the frame.
   - What's unclear: Whether to add a computed property to `LiveFeedbackController` or let `AppDelegate` track the frame separately.
   - Recommendation: Add `var widgetFrame: NSRect? { widgetWindow?.frame }` to `LiveFeedbackController`. This is a one-line addition and the cleanest approach.

3. **Should the diff popup be interactive (e.g., a dismiss button)?**
   - What we know: Requirements say "auto-dismisses after 3 seconds." There is no "undo" button requirement in the popup itself — undo is via the menu item.
   - What's unclear: Whether the popup should be dismissible by clicking (like the live feedback popover).
   - Recommendation: Make the popup dismiss on click (add a mouse-down handler), but keep it non-interactive otherwise (no undo button). This matches macOS HIG for transient info panels.

4. **What to show when no changes were made (fix count = 0)**
   - What we know: `handleLocalFixHotkey()` calls `showHUD(state: .success)` when `fixable.isEmpty`. No history entry is recorded.
   - What's unclear: Should the diff popup appear saying "Nothing to fix"?
   - Recommendation: Do NOT show the diff popup if `fixCount == 0`. The existing HUD `.success` message ("Done!") is sufficient. The popup only appears when there is a before/after diff to show.

---

## Key Implementation Touchpoints in AppDelegate.swift

| Location | Line Approx. | What to Add |
|----------|-------------|-------------|
| `AppDelegate` properties | ~line 18 | `private var quickFixDiffPopup: QuickFixDiffPopupController?` |
| `handleLocalFixHotkey()` — FoundationModels path | ~line 694 | Capture `currentText`, after success: call `recordLocalFixHistoryEntry()` + `showQuickFixDiffPopup()` |
| `handleLocalFixHotkey()` — `applyRuleBasedFixes` call | ~line 709 | Wrap to capture `originalText = currentText` before call |
| `applyRuleBasedFixes(...)` — after `fixCount > 0` | ~line 761 | Pass `originalText` + `nsText as String` back to caller, or call popup/record directly |
| `startProcessingIndicator()` | ~line 1347 | Add `quickFixDiffPopup?.dismiss()` |
| Bottom of `AppDelegate.swift` | after `HUDOverlayController` | New `final class QuickFixDiffPopupController { ... }` |
| `LiveFeedbackController` | after `private var widgetWindow` | Add `var widgetFrame: NSRect? { widgetWindow?.frame }` |

Note: `applyRuleBasedFixes` is currently a `Void`-returning method. To pass `nsText` back to `handleLocalFixHotkey()`, either change its return type to `String?` (the fixed text, or nil if no fixes), or add an `inout` parameter. Returning an optional `String` is cleaner.

---

## Coverage Gate Impact

**Files NOT in the guarded list that will be modified:**
- `AppDelegate.swift` — not guarded, no coverage required
- `LiveFeedbackController` (inside `AppDelegate.swift`) — not guarded

**Guarded files that will be called but NOT modified:**
- `DiffSupport.swift` — called (`charDiff`), but not changed → no new tests needed
- `CorrectionHistoryStore.swift` — called (`append`, `lastSuccessfulEntry`), but not changed → no new tests needed
- `HUDOverlaySupport.swift` — called, not changed → no new tests needed

**Conclusion:** Phase 1 requires zero test file changes. The 100% coverage gate is not threatened.

---

## Sources

### Primary (HIGH confidence)
- Direct code reading of `AppDelegate.swift` (verified line numbers above) — all patterns cited are from actual code in the repo
- Direct code reading of `DiffSupport.swift`, `HUDOverlaySupport.swift`, `CorrectionHistoryStore.swift`, `LiveFeedbackSupport.swift`, `SpellCheckSupport.swift`
- `CLAUDE.md` project guide — architecture overview, coverage gate rules, file locations

### Secondary (MEDIUM confidence)
- `ARCHITECTURE.md`, `STACK.md`, `CONCERNS.md` planning documents — cross-validated against source code

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified in existing codebase code
- Architecture: HIGH — patterns directly observed in AppDelegate.swift
- Pitfalls: HIGH — gap analysis from source code (history not recorded for local fixes confirmed by grep)

**Research date:** 2026-02-26
**Valid until:** 2026-03-28 (stable codebase, AppKit APIs unchanged)
