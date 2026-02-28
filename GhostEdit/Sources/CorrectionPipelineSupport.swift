import Foundation

enum CorrectionPipelineSupport {
    /// Determine which target application to correct text for.
    /// Returns the frontmost app if it's not our own app; otherwise falls back to the cached last-external app.
    enum TargetResolution: Equatable {
        case frontmost
        case cached
        case none
    }

    static func resolveTarget(
        frontmostBundleID: String?,
        ownBundleID: String?,
        cachedAppIsAvailable: Bool,
        cachedAppIsTerminated: Bool
    ) -> TargetResolution {
        if let frontmost = frontmostBundleID, frontmost != ownBundleID {
            return .frontmost
        }
        if cachedAppIsAvailable && !cachedAppIsTerminated {
            return .cached
        }
        return .none
    }

    /// Determine how to capture text from the target application.
    enum TextCaptureStrategy: Equatable {
        case accessibilitySelectedText
        case accessibilityLineAtCursor
        case clipboardFallback
    }

    static func textCaptureStrategy(
        axSelectedText: String?,
        axFullText: String?,
        axCursorPosition: Int?,
        lineExtractionResult: Bool,
        containsObjectReplacement: Bool
    ) -> TextCaptureStrategy {
        // If AX selected text is available and doesn't contain U+FFFC, use it directly
        if let selected = axSelectedText, !selected.isEmpty, !containsObjectReplacement {
            return .accessibilitySelectedText
        }
        // If no selection but full text + cursor available, extract line at cursor
        if axFullText != nil, !containsObjectReplacement, axCursorPosition != nil, lineExtractionResult {
            return .accessibilityLineAtCursor
        }
        // Fall back to clipboard-based copy
        return .clipboardFallback
    }

    /// Determine whether to extract a line at cursor or use full text (local fix pipeline).
    static func lineExtractionStrategy(
        textContainsObjectReplacement: Bool
    ) -> Bool {
        // Skip line extraction when U+FFFC present (Slack inline emojis)
        return !textContainsObjectReplacement
    }

    /// Classify a processing error for display to the user.
    enum ProcessingErrorKind: Equatable {
        case cliNotFound
        case authenticationRequired(provider: String)
        case timedOut(seconds: Int)
        case emptyResponse
        case processFailed(exitCode: Int, detail: String)
        case general(String)
    }

    static func classifyProcessingError(
        exitCode: Int,
        stderr: String,
        stdout: String,
        provider: String,
        timedOut: Bool,
        timeoutSeconds: Int
    ) -> ProcessingErrorKind {
        if timedOut {
            return .timedOut(seconds: timeoutSeconds)
        }
        let normalizedStderr = stderr.lowercased()
        if exitCode == 127 || normalizedStderr.contains("not found") || normalizedStderr.contains("no such file") {
            return .cliNotFound
        }
        if normalizedStderr.contains("api error: 401")
            || normalizedStderr.contains("unauthorized")
            || normalizedStderr.contains("invalid_api_key")
            || normalizedStderr.contains("authentication")
            || normalizedStderr.contains("invalid credentials") {
            return .authenticationRequired(provider: provider)
        }
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStdout.isEmpty && stderr.isEmpty && exitCode == 0 {
            return .emptyResponse
        }
        if exitCode != 0 {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .processFailed(exitCode: exitCode, detail: detail)
        }
        return .general(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Determine the write-back strategy for corrected text.
    enum WriteBackStrategy: Equatable {
        case lineWriteBack
        case axReplacement
        case clipboardPaste
    }

    static func selectWriteBackStrategy(
        hasLineContext: Bool,
        lineWriteBackSucceeded: Bool?,
        axReplacementSucceeded: Bool?,
        axVerified: Bool?,
        clipboardOnly: Bool
    ) -> WriteBackStrategy {
        if clipboardOnly {
            return .clipboardPaste
        }
        if hasLineContext {
            if lineWriteBackSucceeded == true {
                return .lineWriteBack
            }
            // Line write-back failed, fall through
        }
        if axReplacementSucceeded == true {
            if axVerified == true || axVerified == nil {
                // nil means read-back returned nil, treated as success
                return .axReplacement
            }
            // Verification failed
            return .clipboardPaste
        }
        return .clipboardPaste
    }

    /// Determine if we should fall back to clipboard after AX verification.
    static func shouldFallbackToClipboard(
        readBackText: String?,
        correctedText: String
    ) -> Bool {
        // If read-back is nil, treat as success (no fallback needed)
        guard let readBack = readBackText else {
            return false
        }
        // If read-back matches, AX replacement worked
        return readBack != correctedText
    }

    /// Determine the tool label for the local fix pipeline.
    static func toolLabel(
        spellFixedText: String,
        originalText: String,
        modelCorrectedText: String?
    ) -> String? {
        if let modelText = modelCorrectedText {
            let trimmed = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == spellFixedText {
                // Model returned unchanged — use spell-fixed text if it differs
                if spellFixedText == originalText {
                    return nil // Nothing changed at all
                }
                return "Harper + Dictionary"
            }
            return spellFixedText != originalText
                ? "Harper + Local Model"
                : "Local Model"
        }
        // No model path, pure rule-based
        if spellFixedText != originalText {
            return "Harper + Dictionary"
        }
        return nil
    }

    /// Reconstruct full text after correcting a single line.
    static func reconstructTextAfterLineCorrection(
        fullText: String,
        correctedLine: String,
        lineRange: NSRange
    ) -> String {
        let nsFullText = fullText as NSString
        let originalLine = nsFullText.substring(with: lineRange)
        if originalLine.hasSuffix("\n") {
            return nsFullText.replacingCharacters(in: lineRange, with: correctedLine + "\n")
        } else {
            return nsFullText.replacingCharacters(in: lineRange, with: correctedLine)
        }
    }

    /// Calculate the new cursor position after correcting a line.
    static func cursorPositionAfterLineCorrection(
        lineRangeLocation: Int,
        correctedLineLength: Int
    ) -> Int {
        return lineRangeLocation + correctedLineLength
    }

    /// Clamp cursor position to valid range after text replacement.
    static func clampedCursorPosition(
        cursorLocation: Int,
        cursorDelta: Int,
        newTextLength: Int
    ) -> Int {
        return max(0, min(cursorLocation + cursorDelta, newTextLength))
    }

    /// Check if clipboard text is a sentinel (not actual user content).
    static func isSentinelValue(_ text: String, sentinel: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == sentinel
    }
}
