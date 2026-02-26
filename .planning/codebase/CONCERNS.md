# Codebase Concerns

**Analysis Date:** 2026-02-26

## Monolithic Class Size

**AppDelegate.swift:**
- Issue: Single file contains 6,195 lines with 8 major classes (AppDelegate, DeveloperConsoleController, DiffPreviewController, StreamingPreviewController, LineNumberRulerView, SettingsWindowController, HistoryWindowController, HUDOverlayController)
- Files: `GhostEdit/Sources/AppDelegate.swift` (243 KB)
- Impact: Makes the file difficult to navigate, test indirectly (no test coverage required, but increased bug risk), and modify without breaking multiple concerns. IDE indexing and compilation times suffer with very large files.
- Fix approach: Extract each controller/view into separate files (e.g., `DiffPreviewController.swift`, `StreamingPreviewController.swift`, `SettingsWindowController.swift`, `HistoryWindowController.swift`). Keep only `AppDelegate` class in its own file.

## Force Unwrapping in Token Preservation

**TokenPreservationSupport.swift:**
- Issue: Three `try!` force unwraps used for NSRegularExpression initialization (lines 31, 206, 207)
- Files: `GhostEdit/Sources/TokenPreservationSupport.swift`
- Impact: If a regex pattern is malformed, the app will crash at runtime with no graceful fallback. These patterns are hardcoded, so compile-time verification is not possible.
- Fix approach: Replace `try!` with proper error handling. Create a function that safely initializes regexes and returns an empty list or safe default on failure. Log initialization failures to developer console.

## Force Casting in Accessibility

**AccessibilityTextSupport.swift:**
- Issue: Three force casts `as! AXUIElement` (lines 41, 71, 98) without nil-coalescing or safe alternatives
- Files: `GhostEdit/Sources/AccessibilityTextSupport.swift`
- Impact: If the AX API returns an unexpected type, the app crashes. While the AX framework's return types should be predictable, this is a system API boundary where assumptions can break with macOS updates.
- Fix approach: Replace force casts with optional binding and return `false` or `nil` on mismatch. Add developer logging for unexpected type violations.

## Force Unwrapping AXValueCreate

**AccessibilityTextSupport.swift:**
- Issue: Force unwrap of `AXValueCreate()` result (line 102) with inline comment acknowledging the risk
- Files: `GhostEdit/Sources/AccessibilityTextSupport.swift` (line 102)
- Impact: The AX framework may return nil in edge cases or after system updates. This will crash the undo/text replacement functionality.
- Fix approach: Safely unwrap and return `false` if creation fails. Log the failure to developer mode.

## Potential Race Condition in Clipboard Restoration

**AppDelegate.swift:**
- Issue: Clipboard snapshot is saved at trigger time and restored without explicit synchronization. Multiple rapid hotkey presses or background clipboard access between capture and restore could restore stale data.
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 37, 1004-1007, 1131, 1150)
- Impact: User might paste incorrect text if clipboard was modified externally during the correction window. Rare but user-visible data loss risk.
- Fix approach: Capture a UUID-tagged snapshot when hotkey fires. On restore, verify the snapshot is still valid (e.g., check file modification time). Add a timeout—if restoration takes >30 seconds, discard the old snapshot to prevent confusion.

## Unprotected Shared State in AppDelegate

**AppDelegate.swift:**
- Issue: Multiple non-atomic properties accessed from different queues: `isProcessing`, `clipboardSnapshot`, `targetAppAtTrigger`, `didShowAccessibilityGuidance`, window controller references
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 34-39)
- Impact: If hotkey fires during streaming preview, settings window interaction, or concurrent corrections, state may become corrupted. Tests won't catch this because they run serially.
- Fix approach: Wrap mutable state in a serial DispatchQueue or use NSLock for critical sections. Create a dedicated "AppState" struct and manage it atomically.

## Persistent Session Lifecycle Not Fully Guarded

**ShellRunner.swift:**
- Issue: Persistent session is spawned asynchronously in background (line 91-95) but the process may exit or fail without being immediately detected. Subsequent corrections will attempt to use a dead session.
- Files: `GhostEdit/Sources/ShellRunner.swift` (lines 91-95, 169-175)
- Impact: First correction after a session death will incur the full one-shot CLI overhead (no speed benefit), and the UI will show "Using persistent session" in logs when it's actually falling back.
- Fix approach: Implement periodic health checks on the persistent session (e.g., every 30 seconds). Kill and respawn if unhealthy. Add a "session ready" event observers pattern.

## GitHub API Hardcoded URL and Synchronous Network Call

**AppDelegate.swift:**
- Issue: Update check makes a synchronous network request on main thread via `semaphore.wait()` (lines 1808-1828)
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 1808-1828)
- Impact: If GitHub API is slow or unreachable, the app UI will freeze for up to 10 seconds (timeout interval). No retry logic. If the URL ever moves or GitHub changes the API format, the feature breaks silently.
- Fix approach: Move to async/await. Use URLSession.shared with a proper async completion. Add exponential backoff retry. Store last-known version in cache to avoid repeated network calls. Set timeout to 5 seconds max.

## Token Placeholder Collision Risk

**TokenPreservationSupport.swift:**
- Issue: Placeholders are generated with an index-based suffix (e.g., `__GHOSTEDIT_KEEP_0__`). If the original text happens to contain this exact placeholder string, restoration will fail silently or create duplicates.
- Files: `GhostEdit/Sources/TokenPreservationSupport.swift` (lines 18, 42-71, 108-116)
- Impact: Edge case, but if user has text like "Replace __GHOSTEDIT_KEEP_0__ with the actual email", the placeholder will conflict and the token restoration will be incorrect.
- Fix approach: Use UUID-based placeholders instead of indices. Verify placeholders are unique against the source text before protection. Add a collision detection test.

## Stream Parsing Not Validated

**PersistentCLISession.swift:**
- Issue: NDJSON stream parsing (line 203-210) assumes valid JSON structure without comprehensive validation. Malformed or truncated response from CLI will throw but the error type is generic.
- Files: `GhostEdit/Sources/PersistentCLISession.swift` (lines 203-210, 262-275)
- Impact: If the Claude CLI returns malformed stream-json (e.g., due to a bug or network corruption), the user sees a vague "Malformed CLI response" error with limited debugging info.
- Fix approach: Add detailed error logging with the first 500 bytes of the malformed response. Validate JSON structure before parsing. Add stream integrity checks (e.g., expected message count).

## Weak Self in View Controller Blocks

**AppDelegate.swift:**
- Issue: Multiple `[weak self]` captures in long-lived blocks (lines 1064-1087, 1078-1087, 1094, 1860, etc.). If the closure outlives AppDelegate's deallocation, `self` will be nil and the block does nothing silently.
- Files: `GhostEdit/Sources/AppDelegate.swift`
- Impact: If the app terminates or AppDelegate is deallocated during streaming or background corrections, the completion handlers vanish without cleanup. UI state may be inconsistent (e.g., `isProcessing` left true).
- Fix approach: Add debug assertions or logging when `self` becomes nil inside critical closures. Implement a cancellation token passed to async tasks so cleanup can be explicit.

## No Timeout on Accessibility API Calls

**AccessibilityTextSupport.swift:**
- Issue: `AXUIElementCopyAttributeValue()` and `AXUIElementSetAttributeValue()` calls (lines 15-21) have no timeout. If the target application hangs or is frozen, GhostEdit will block on the AX call.
- Files: `GhostEdit/Sources/AccessibilityTextSupport.swift`
- Impact: If user selects text in a frozen app and presses Cmd+E, GhostEdit can hang indefinitely while waiting for the AX API. The app appears unresponsive.
- Fix approach: Wrap AX calls in a timeout using `DispatchQueue.global()` and `DispatchSemaphore` with a 3-second timeout. Fall back to clipboard if AX times out.

## Hardcoded Timeout Values

**Multiple files:**
- Issue: Timeout values are hardcoded throughout (60s in ConfigManager, 3s in health checks, 30s in persistent session init, 10s in update check, 2s in process termination grace period)
- Files: `GhostEdit/Sources/ConfigManager.swift`, `GhostEdit/Sources/PersistentCLISession.swift`, `GhostEdit/Sources/AppDelegate.swift`, `GhostEdit/Sources/ShellRunner.swift`
- Impact: Different timeouts for different operations make behavior unpredictable. No central configuration means changes require multi-file edits.
- Fix approach: Create a `TimeoutConfiguration` struct in a new `TimeoutSupport.swift` file. Define all timeouts as named constants with clear intent comments.

## No Validation of Config File Structure

**ConfigManager.swift:**
- Issue: JSON decoding of `config.json` uses simple try-catch with no validation of required fields or semantic constraints (e.g., can historyLimit be -1?)
- Files: `GhostEdit/Sources/ConfigManager.swift`
- Impact: If config file is manually edited with invalid values (negative timeout, empty provider), the app may behave unexpectedly or crash downstream.
- Fix approach: Add a validation function after decoding. Clamp values to safe ranges. Provide detailed error messages if config is invalid.

## History File Could Grow Without Bound if Limit is 0 or Negative

**CorrectionHistoryStore.swift:**
- Issue: The `normalizedEntries()` function (line 66-72) uses `max(1, limit)`, but this only prevents 0. If limit is somehow negative after loading config, it won't clip properly.
- Files: `GhostEdit/Sources/CorrectionHistoryStore.swift` (line 67)
- Impact: While unlikely due to `AppConfig.historyLimit` being an Int, a corrupted config or edge case could cause unbounded history growth.
- Fix approach: Validate historyLimit is positive when loading config. Add a minimum hard cap (e.g., 10) even if user sets it lower.

## Emoji Restoration Heuristic Is Best-Effort

**TokenPreservationSupport.swift:**
- Issue: The final fallback in `bestEffortRestore()` (lines 106-116) only restores tokens that are still present in the output. If the AI removed an emoji like `:smile:`, it stays removed with no error.
- Files: `GhostEdit/Sources/TokenPreservationSupport.swift` (lines 106-116)
- Impact: User expects protected tokens to always be preserved. Silent partial restoration is confusing—they won't notice an emoji was dropped until they look at the result.
- Fix approach: Log when best-effort restoration finds missing tokens. Return a tuple `(restoredText, missingTokens)` and notify the user if any protected tokens were lost. Offer "undo" option.

## No Mechanism to Handle Concurrent Corrections

**AppDelegate.swift:**
- Issue: `isProcessing` flag prevents re-entry, but if user holds down hotkey or clicks menu items rapidly, requests can queue or be lost. No queue or cancellation token.
- Files: `GhostEdit/Sources/AppDelegate.swift` (line 34)
- Impact: User's second hotkey press is silently dropped with only a status message update. They may not realize their correction didn't fire.
- Fix approach: Queue up to N pending requests (e.g., 3). Dequeue and process when the current one completes. Or implement explicit cancellation token passing.

## Streaming Preview Window Can Be Left Open if App Crashes

**AppDelegate.swift:**
- Issue: `streamingPreviewController` is held as a property but not explicitly closed on app termination or error recovery
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 17-18)
- Impact: If the app crashes while a streaming preview is open, the preview window lingers orphaned on screen.
- Fix approach: In `applicationWillTerminate()`, explicitly close all controller windows. Add a `closeAllWindows()` method.

## No Recovery from Invalid History Entries

**CorrectionHistoryStore.swift:**
- Issue: If a single entry in `history.json` is corrupted, the entire history decoding fails and all entries are lost
- Files: `GhostEdit/Sources/CorrectionHistoryStore.swift` (lines 74-84)
- Impact: One bad byte in the JSON file means users lose their entire correction history.
- Fix approach: Implement partial recovery: decode entries one-by-one and skip malformed ones. Log skipped entries. Rebuild the history file with only valid entries.

## Leaking Pipes and Processes on Error

**PersistentCLISession.swift & ShellRunner.swift:**
- Issue: If a process fails to spawn or is terminated abnormally, the pipes and file handles may not be properly cleaned up in all error paths
- Files: `GhostEdit/Sources/PersistentCLISession.swift` (lines 157-161), `GhostEdit/Sources/ShellRunner.swift` (lines 518-522)
- Impact: Repeated failures could accumulate leaked file descriptors, eventually exhausting system limits and making the app unresponsive.
- Fix approach: Implement a `teardownLocked()` method that explicitly closes all handles and cleans up pipes. Call it in all error paths and in the deinit.

## Silent Failure if Accessibility Permission is Denied

**AppDelegate.swift:**
- Issue: `ensureAccessibilityPermission()` (line 74) is called with `promptSystemDialog: false` at startup, so users may never be prompted. If permission is denied, all corrections silently fall back to clipboard mode without user feedback.
- Files: `GhostEdit/Sources/AppDelegate.swift` (line 74)
- Impact: User thinks the app isn't working because corrections aren't pasting back. They don't realize they need to grant accessibility permission.
- Fix approach: If accessibility is unavailable after first hotkey press, show a prominent alert explaining why and guiding them to System Settings. Cache this alert state to show it only once per session.

## Model List Could Be Out of Sync with Claude CLI

**ConfigManager.swift:**
- Issue: Available models for Claude (lines 48-56) are hardcoded. When Anthropic releases new models, users must update the app to see them. Old model names like "haiku" may become deprecated.
- Files: `GhostEdit/Sources/ConfigManager.swift` (lines 48-56)
- Impact: User selects a model that no longer exists, the correction fails with an error. No way to discover available models at runtime.
- Fix approach: Query the Claude CLI at startup for available models using `--models` flag. Cache the list with an expiry. Fall back to hardcoded list if query fails.

## No Explicit Memory Management in Streaming

**StreamingPreviewSupport.swift & ShellRunner.swift:**
- Issue: The streaming path accumulates the entire corrected text in memory as chunks arrive (line 596 in ShellRunner). Very large AI responses (>1MB) could exhaust memory on older Macs.
- Files: `GhostEdit/Sources/ShellRunner.swift` (lines 589-602)
- Impact: If a user attempts to fix very large text (unlikely but possible), memory pressure could trigger system warnings or crashes.
- Fix approach: Implement a max size cap (e.g., 10MB) and reject corrections that exceed it. Stream to disk temporarily if needed. Notify user if response is truncated.

## Notification Callbacks Not Unregistered Properly

**AppDelegate.swift:**
- Issue: `startObservingActiveApplication()` (line 73) registers workspace notifications but the unregistration in `applicationWillTerminate()` (line 88) may not catch all observer types
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 88)
- Impact: If the app adds new observers without unregistering them, stale notifications could fire after deallocation, causing crashes.
- Fix approach: Maintain an array of `NSObjectProtocol` observer tokens. Explicitly unregister each in `applicationWillTerminate()`.

## No Gradual Rollout or Feature Flags

**AppDelegate.swift:**
- Issue: New features like live feedback, streaming preview, and writing coach are enabled via config boolean with no way to gradually roll them out or A/B test
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 77-79, 193-200)
- Impact: A bug in a new feature could affect all users who enable it. No way to monitor adoption or disable a feature without an app update.
- Fix approach: Implement feature flags with version-gated rollout (e.g., "live_feedback_rollout: 25%" in cloud config). Add telemetry to track adoption.

## Shell Injection Risk in PersistentShellSession

**PersistentShellSession.swift:**
- Issue: The `shellQuote()` function (presumed, not shown) is critical for preventing shell injection. If it has a bug, arbitrary shell commands could be executed.
- Files: `GhostEdit/Sources/PersistentShellSession.swift` (line 56)
- Impact: Even if unlikely, shell injection could allow local privilege escalation or data exfiltration if the CLI tool is compromised.
- Fix approach: Ensure `shellQuote()` properly escapes all shell metacharacters. Use `ProcessInfo` to build commands with proper separation instead of string interpolation. Add unit tests for edge cases.

## No Undo Functionality for Corrections

**AppDelegate.swift:**
- Issue: "Undo Last Correction" menu item (lines 149-157) is implemented but there's no undo queue or proper state management. Users can only undo the most recent correction.
- Files: `GhostEdit/Sources/AppDelegate.swift` (lines 149-157, 1268-1280)
- Impact: If a user makes multiple corrections, they can only undo the very last one. Multi-level undo is not possible.
- Fix approach: Implement an undo stack with N levels (e.g., 10 most recent). Allow Cmd+Z to undo multiple steps. Add a "redo" option.

## No Verification of CLI Checksum or Signature

**ShellRunner.swift:**
- Issue: The detected CLI path (lines 405-429) is used without verifying its integrity. A compromised `claude` binary could execute arbitrary code.
- Files: `GhostEdit/Sources/ShellRunner.swift` (lines 405-429)
- Impact: If an attacker replaces the CLI binary in the user's PATH, GhostEdit will blindly execute it with the user's authentication token.
- Fix approach: Verify CLI binary is from Anthropic using code signing or checksum. Warn user if binary is unsigned. Recommend installing CLI via official package manager (brew, etc.).

## Verbose Logging Can Leak Sensitive Data

**DeveloperModeSupport.swift:**
- Issue: Developer mode logs full correction text and CLI arguments (visible in the UI), which could contain passwords, API keys, or private information
- Files: Related to developer console in `AppDelegate.swift`
- Impact: If user enables developer mode and takes a screenshot, sensitive data might be visible in logs.
- Fix approach: Add a redaction option in developer mode. Truncate sensitive data in logs (first 50 chars + "..."). Option to exclude certain log phases.

## Import Cycle Risk with Support Modules

**Multiple files:**
- Issue: Support modules are designed to be enum namespaces with static methods, but some may have subtle circular dependencies (e.g., if TokenPreservationSupport imports DiffSupport and vice versa)
- Files: All files in `GhostEdit/Sources/`
- Impact: Build failures or subtle linker errors if cycles exist. Difficult to refactor.
- Fix approach: Document the dependency graph. Use a build phase check to detect cycles. Keep support modules as pure functions with minimal imports.

---

*Concerns audit: 2026-02-26*
