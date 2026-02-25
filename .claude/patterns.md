# GhostEdit Code Patterns & Gotchas

## Pattern: Support Modules
All support files are `enum` namespaces with only `static` methods. No instances. Import Foundation only (no AppKit). This keeps them testable.
```swift
enum FooSupport {
    static func bar() -> String { ... }
}
```

## Pattern: History Data Flow
1. `historyStore.load()` returns entries oldest-first (as stored in JSON)
2. `refreshHistoryWindowIfVisible()` reverses them (newest-first)
3. `HistoryWindowController.update(entries:)` stores both `entries` and `rows` arrays
4. `applyFilters()` zips entries+rows, filters, then splits back into `filteredEntries`/`filteredRows`
5. ALL table view methods use `filteredRows`/`filteredEntries` (not `rows`/`entries`)

## Pattern: Status Badge
The history status badge uses `filteredEntries[row].succeeded` boolean directly — NOT string matching on the status text. Badge subview lookup uses `NSUserInterfaceItemIdentifier` for reliability.

## Pattern: HUD States
```swift
.working           — blue tint, spinner, spectacles on ghost
.success           — green tint, no spinner
.successWithCount  — green tint, shows "Done! (N chars fixed)"
.error(String)     — red tint, shows error message or default
```

## Pattern: Diff Display
- `wordDiff()` for summary text and change counts
- `charDiff()` for streaming preview highlighting (more precise)
- Both use same Myers algorithm internally

## Gotcha: NSView.tag is Read-Only in AppKit
Unlike UIKit, `NSView.tag` is a computed read-only property. Use `identifier` (NSUserInterfaceItemIdentifier) instead for view lookup.

## Gotcha: SourceKit Cross-Module Errors
SourceKit shows "Cannot find 'AppConfig' in scope" etc. for types defined in GhostEditCore when editing AppDelegate.swift. These are false positives. If `xcodebuild build` succeeds, they're safe to ignore.

## Gotcha: Pre-Commit Hook Runs Full Test Suite
The `.githooks/pre-commit` runs `scripts/run_tests_with_coverage.sh` which:
1. Builds test target with coverage enabled
2. Runs all tests
3. Validates 100% line coverage on 26 guarded files
4. If any file drops below 100%, commit is REJECTED

This means every commit takes ~1-2 minutes. The pre-push hook runs the same thing.

## Gotcha: Version in project.yml is Stale
The `project.yml` (XcodeGen spec) still says version 5.0.1 / build 21. The actual version lives in `GhostEdit.xcodeproj/project.pbxproj`. Always bump in pbxproj, not project.yml.

## Gotcha: Two xcodeproj Files
The GrammarFixer directory has both `GhostEdit.xcodeproj` (active) and `GrammarFixer.xcodeproj` (legacy/empty). Always use `-project GhostEdit.xcodeproj` in xcodebuild commands.

## Gotcha: recordHistoryEntry Threading
- Success path: called on background thread (DispatchQueue.global)
- Error path: called on main thread (inside DispatchQueue.main.async)
- `refreshHistoryWindowIfVisible()` always dispatches UI update to main

## Gotcha: Ad-Hoc Code Signing
The app uses ad-hoc signing (`codesign --force --deep --sign -`). This is needed after copying the built app to /Applications.

## Convention: Menu Bar
- App runs as `LSUIElement = true` (no dock icon, menu bar only)
- Menu items use SF Symbols via `NSImage(systemSymbolName:accessibilityDescription:)`
- Status item configured in `configureStatusItem()` (lines 85-315)

## Convention: Window Restoration
All 5 windows use `setFrameAutosaveName()` with conditional centering:
```swift
window.setFrameAutosaveName("GhostEditFoo")
if !window.setFrameUsingName("GhostEditFoo") { window.center() }
```
