import XCTest
@testable import GhostEditCore

final class CorrectionPipelineSupportTests: XCTestCase {

    // MARK: - resolveTarget

    func testResolveTargetFrontmostAppNotSelf() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: "com.other.app",
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: false,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(result, .frontmost)
    }

    func testResolveTargetFrontmostAppIsSelfFallsToCached() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: "com.ghostedit.app",
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: true,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(result, .cached)
    }

    func testResolveTargetFrontmostAppIsSelfCachedTerminated() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: "com.ghostedit.app",
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: true,
            cachedAppIsTerminated: true
        )
        XCTAssertEqual(result, .none)
    }

    func testResolveTargetFrontmostNilNoCached() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: nil,
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: false,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(result, .none)
    }

    func testResolveTargetFrontmostNilWithCached() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: nil,
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: true,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(result, .cached)
    }

    func testResolveTargetBothBundleIDsNil() {
        let result = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: nil,
            ownBundleID: nil,
            cachedAppIsAvailable: false,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(result, .none)
    }

    // MARK: - textCaptureStrategy

    func testTextCaptureViaAccessibility() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "Hello world",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .accessibilitySelectedText)
    }

    func testTextCaptureAccessibilityWithObjectReplacement() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "Hello \u{FFFC} world",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: true
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    func testTextCaptureLineAtCursor() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: "Line 1\nLine 2\nLine 3",
            axCursorPosition: 8,
            lineExtractionResult: true,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .accessibilityLineAtCursor)
    }

    func testTextCaptureLineAtCursorFailsNoExtractionResult() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: "Line 1\nLine 2",
            axCursorPosition: 5,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    func testTextCaptureClipboardFallback() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    func testTextCaptureEmptySelectedText() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    func testTextCaptureLineAtCursorWithObjectReplacement() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: "Text with \u{FFFC}",
            axCursorPosition: 5,
            lineExtractionResult: true,
            containsObjectReplacement: true
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    func testTextCaptureNoCursorPosition() {
        let result = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: "Some text",
            axCursorPosition: nil,
            lineExtractionResult: true,
            containsObjectReplacement: false
        )
        XCTAssertEqual(result, .clipboardFallback)
    }

    // MARK: - lineExtractionStrategy

    func testLineExtractionAllowedWhenNoObjectReplacement() {
        XCTAssertTrue(CorrectionPipelineSupport.lineExtractionStrategy(textContainsObjectReplacement: false))
    }

    func testLineExtractionSkippedWhenObjectReplacement() {
        XCTAssertFalse(CorrectionPipelineSupport.lineExtractionStrategy(textContainsObjectReplacement: true))
    }

    // MARK: - classifyProcessingError

    func testClassifyTimedOut() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: -1, stderr: "", stdout: "", provider: "claude",
            timedOut: true, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .timedOut(seconds: 30))
    }

    func testClassifyCLINotFoundExitCode127() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 127, stderr: "", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .cliNotFound)
    }

    func testClassifyCLINotFoundStderrMessage() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "claude: command not found", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .cliNotFound)
    }

    func testClassifyCLINotFoundNoSuchFile() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "No such file or directory", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .cliNotFound)
    }

    func testClassifyAuthenticationRequired401() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "API Error: 401 Unauthorized", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .authenticationRequired(provider: "claude"))
    }

    func testClassifyAuthenticationRequiredInvalidKey() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Error: invalid_api_key", stdout: "", provider: "gemini",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .authenticationRequired(provider: "gemini"))
    }

    func testClassifyAuthenticationRequiredInvalidCredentials() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Invalid credentials for this provider", stdout: "", provider: "codex",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .authenticationRequired(provider: "codex"))
    }

    func testClassifyEmptyResponse() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 0, stderr: "", stdout: "  ", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .emptyResponse)
    }

    func testClassifyProcessFailedWithStderr() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Something went wrong", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .processFailed(exitCode: 1, detail: "Something went wrong"))
    }

    func testClassifyProcessFailedWithStdout() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 2, stderr: "  ", stdout: "Error output here", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .processFailed(exitCode: 2, detail: "Error output here"))
    }

    func testClassifyGeneralError() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 0, stderr: "Some warning", stdout: "result text", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .general("Some warning"))
    }

    // MARK: - selectWriteBackStrategy

    func testWriteBackClipboardOnlyMode() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: true, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: nil, axVerified: nil, clipboardOnly: true
        )
        XCTAssertEqual(result, .clipboardPaste)
    }

    func testWriteBackLineContextSuccess() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: true, lineWriteBackSucceeded: true,
            axReplacementSucceeded: nil, axVerified: nil, clipboardOnly: false
        )
        XCTAssertEqual(result, .lineWriteBack)
    }

    func testWriteBackLineContextFailsFallsToAX() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: true, lineWriteBackSucceeded: false,
            axReplacementSucceeded: true, axVerified: true, clipboardOnly: false
        )
        XCTAssertEqual(result, .axReplacement)
    }

    func testWriteBackAXReplacementVerified() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: true, axVerified: true, clipboardOnly: false
        )
        XCTAssertEqual(result, .axReplacement)
    }

    func testWriteBackAXReplacementVerifiedNilReadback() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: true, axVerified: nil, clipboardOnly: false
        )
        XCTAssertEqual(result, .axReplacement)
    }

    func testWriteBackAXReplacementUnverified() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: true, axVerified: false, clipboardOnly: false
        )
        XCTAssertEqual(result, .clipboardPaste)
    }

    func testWriteBackAXReplacementFailed() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: false, axVerified: nil, clipboardOnly: false
        )
        XCTAssertEqual(result, .clipboardPaste)
    }

    func testWriteBackNoLineNoAX() {
        let result = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false, lineWriteBackSucceeded: nil,
            axReplacementSucceeded: nil, axVerified: nil, clipboardOnly: false
        )
        XCTAssertEqual(result, .clipboardPaste)
    }

    // MARK: - shouldFallbackToClipboard

    func testFallbackNilReadback() {
        XCTAssertFalse(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: nil, correctedText: "Hello"
        ))
    }

    func testFallbackMatchingReadback() {
        XCTAssertFalse(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: "Hello", correctedText: "Hello"
        ))
    }

    func testFallbackMismatchedReadback() {
        XCTAssertTrue(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: "Different text", correctedText: "Hello"
        ))
    }

    // MARK: - toolLabel

    func testToolLabelModelUnchanged() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "fixed text",
            originalText: "original text",
            modelCorrectedText: "fixed text"
        )
        XCTAssertEqual(result, "Harper + Dictionary")
    }

    func testToolLabelModelEmpty() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "fixed text",
            originalText: "original text",
            modelCorrectedText: ""
        )
        XCTAssertEqual(result, "Harper + Dictionary")
    }

    func testToolLabelNothingChanged() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "same",
            originalText: "same",
            modelCorrectedText: "same"
        )
        XCTAssertNil(result)
    }

    func testToolLabelModelChanged() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "same",
            originalText: "same",
            modelCorrectedText: "model output"
        )
        XCTAssertEqual(result, "Local Model")
    }

    func testToolLabelBothChanged() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "spell fixed",
            originalText: "original",
            modelCorrectedText: "model output"
        )
        XCTAssertEqual(result, "Harper + Local Model")
    }

    func testToolLabelNoModel() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "fixed",
            originalText: "original",
            modelCorrectedText: nil
        )
        XCTAssertEqual(result, "Harper + Dictionary")
    }

    func testToolLabelNoModelNoChange() {
        let result = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "same",
            originalText: "same",
            modelCorrectedText: nil
        )
        XCTAssertNil(result)
    }

    // MARK: - reconstructTextAfterLineCorrection

    func testReconstructWithTrailingNewline() {
        let result = CorrectionPipelineSupport.reconstructTextAfterLineCorrection(
            fullText: "Line 1\nLine 2\nLine 3",
            correctedLine: "Fixed Line 2",
            lineRange: NSRange(location: 7, length: 7)
        )
        XCTAssertEqual(result, "Line 1\nFixed Line 2\nLine 3")
    }

    func testReconstructWithNewlineInOriginal() {
        let result = CorrectionPipelineSupport.reconstructTextAfterLineCorrection(
            fullText: "Line 1\nLine 2\n",
            correctedLine: "Fixed",
            lineRange: NSRange(location: 7, length: 7)
        )
        XCTAssertEqual(result, "Line 1\nFixed\n")
    }

    func testReconstructLastLineNoNewline() {
        let result = CorrectionPipelineSupport.reconstructTextAfterLineCorrection(
            fullText: "Line 1\nLine 2",
            correctedLine: "Fixed 2",
            lineRange: NSRange(location: 7, length: 6)
        )
        XCTAssertEqual(result, "Line 1\nFixed 2")
    }

    // MARK: - cursorPositionAfterLineCorrection

    func testCursorPositionAfterLineCorrection() {
        XCTAssertEqual(
            CorrectionPipelineSupport.cursorPositionAfterLineCorrection(
                lineRangeLocation: 10, correctedLineLength: 15
            ), 25
        )
    }

    // MARK: - clampedCursorPosition

    func testClampedCursorPositionNormal() {
        XCTAssertEqual(
            CorrectionPipelineSupport.clampedCursorPosition(
                cursorLocation: 10, cursorDelta: 5, newTextLength: 100
            ), 15
        )
    }

    func testClampedCursorPositionNegative() {
        XCTAssertEqual(
            CorrectionPipelineSupport.clampedCursorPosition(
                cursorLocation: 2, cursorDelta: -10, newTextLength: 100
            ), 0
        )
    }

    func testClampedCursorPositionExceedsLength() {
        XCTAssertEqual(
            CorrectionPipelineSupport.clampedCursorPosition(
                cursorLocation: 90, cursorDelta: 20, newTextLength: 100
            ), 100
        )
    }

    // MARK: - isSentinelValue

    func testIsSentinelValueMatches() {
        XCTAssertTrue(CorrectionPipelineSupport.isSentinelValue(
            "__GHOSTEDIT_SENTINEL_abc__", sentinel: "__GHOSTEDIT_SENTINEL_abc__"
        ))
    }

    func testIsSentinelValueEmpty() {
        XCTAssertTrue(CorrectionPipelineSupport.isSentinelValue("  ", sentinel: "sentinel"))
    }

    func testIsSentinelValueRealText() {
        XCTAssertFalse(CorrectionPipelineSupport.isSentinelValue(
            "Hello world", sentinel: "__GHOSTEDIT_SENTINEL_abc__"
        ))
    }

    func testIsSentinelValueWithWhitespace() {
        XCTAssertTrue(CorrectionPipelineSupport.isSentinelValue(
            "  __GHOSTEDIT_SENTINEL_abc__  ", sentinel: "__GHOSTEDIT_SENTINEL_abc__"
        ))
    }

    func testClassifyAuthenticationUnauthorized() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Unauthorized access denied", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .authenticationRequired(provider: "claude"))
    }

    func testClassifyAuthenticationKeyword() {
        let result = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Authentication failed", stdout: "", provider: "claude",
            timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(result, .authenticationRequired(provider: "claude"))
    }
}
