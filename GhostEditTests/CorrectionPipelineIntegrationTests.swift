import XCTest
@testable import GhostEditCore

final class CorrectionPipelineIntegrationTests: XCTestCase {

    // MARK: - End-to-end pipeline scenarios

    func testNonStreamingCorrectionPreservesTokens() {
        let text = "This has a url https://example.com and @mention in it teh text"
        let protection = TokenPreservationSupport.protectTokens(in: text)
        XCTAssertTrue(protection.hasProtectedTokens)
        // After "correction", tokens should survive restoration
        let corrected = protection.protectedText.replacingOccurrences(of: "teh", with: "the")
        let restored = TokenPreservationSupport.restoreTokens(in: corrected, tokens: protection.tokens)
        XCTAssertTrue(restored.contains("https://example.com"))
        XCTAssertTrue(restored.contains("@mention"))
    }

    func testTargetResolutionAndTextCaptureFlow() {
        // Step 1: Resolve target
        let target = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: "com.apple.TextEdit",
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: false,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(target, .frontmost)

        // Step 2: Text capture strategy with selected text
        let strategy = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "Hello wrold",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(strategy, .accessibilitySelectedText)
    }

    func testWriteBackStrategyDecisionChain() {
        // Scenario: Line context write-back fails, AX replacement succeeds and is verified
        let strategy = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: true,
            lineWriteBackSucceeded: false,
            axReplacementSucceeded: true,
            axVerified: true,
            clipboardOnly: false
        )
        XCTAssertEqual(strategy, .axReplacement)
    }

    func testWriteBackStrategyAXUnverifiedFallsToClipboard() {
        let strategy = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false,
            lineWriteBackSucceeded: nil,
            axReplacementSucceeded: true,
            axVerified: false,
            clipboardOnly: false
        )
        XCTAssertEqual(strategy, .clipboardPaste)
    }

    func testClipboardOnlyModeBypassesAX() {
        let strategy = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: true,
            lineWriteBackSucceeded: true,
            axReplacementSucceeded: true,
            axVerified: true,
            clipboardOnly: true
        )
        XCTAssertEqual(strategy, .clipboardPaste)
    }

    // MARK: - Error classification scenarios

    func testCLINotFoundTriggersCorrectClassification() {
        let error = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 127, stderr: "/usr/local/bin/claude: No such file or directory",
            stdout: "", provider: "claude", timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(error, .cliNotFound)
    }

    func testClaudeAuthErrorClassification() {
        let error = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "API Error: 401 - Invalid API key",
            stdout: "", provider: "claude", timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(error, .authenticationRequired(provider: "claude"))
    }

    func testGeminiAuthErrorClassification() {
        let error = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 1, stderr: "Error: invalid_api_key for gemini service",
            stdout: "", provider: "gemini", timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(error, .authenticationRequired(provider: "gemini"))
    }

    func testTimeoutErrorClassification() {
        let error = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: -1, stderr: "", stdout: "",
            provider: "claude", timedOut: true, timeoutSeconds: 30
        )
        XCTAssertEqual(error, .timedOut(seconds: 30))
    }

    func testEmptyResponseClassification() {
        let error = CorrectionPipelineSupport.classifyProcessingError(
            exitCode: 0, stderr: "", stdout: "",
            provider: "claude", timedOut: false, timeoutSeconds: 30
        )
        XCTAssertEqual(error, .emptyResponse)
    }

    // MARK: - Text capture strategies for different apps

    func testSlackTextCaptureUsesClipboard() {
        // Slack uses U+FFFC for inline emojis
        let strategy = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "Hello \u{FFFC} world",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: true
        )
        XCTAssertEqual(strategy, .clipboardFallback)
    }

    func testLineExtractionSkippedForObjectReplacement() {
        XCTAssertFalse(CorrectionPipelineSupport.lineExtractionStrategy(
            textContainsObjectReplacement: true
        ))
    }

    func testNoSelectionExtractsLineAtCursor() {
        let strategy = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: nil,
            axFullText: "Line 1\nLine 2\nLine 3",
            axCursorPosition: 10,
            lineExtractionResult: true,
            containsObjectReplacement: false
        )
        XCTAssertEqual(strategy, .accessibilityLineAtCursor)
    }

    // MARK: - Line reconstruction scenarios

    func testLineReconstructionPreservesNewlines() {
        let fullText = "First line\nSecond line\nThird line"
        let corrected = "Fixed second line"
        let result = CorrectionPipelineSupport.reconstructTextAfterLineCorrection(
            fullText: fullText,
            correctedLine: corrected,
            lineRange: NSRange(location: 11, length: 12)
        )
        XCTAssertEqual(result, "First line\nFixed second line\nThird line")
    }

    func testCursorClampingAtBounds() {
        XCTAssertEqual(CorrectionPipelineSupport.clampedCursorPosition(
            cursorLocation: 100, cursorDelta: -200, newTextLength: 50
        ), 0)
        XCTAssertEqual(CorrectionPipelineSupport.clampedCursorPosition(
            cursorLocation: 100, cursorDelta: 200, newTextLength: 50
        ), 50)
    }

    // MARK: - Tool label determination for local fix

    func testToolLabelHarperOnlyWhenModelUnchanged() {
        let label = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "The corrected text",
            originalText: "Teh corrected text",
            modelCorrectedText: "The corrected text"
        )
        XCTAssertEqual(label, "Harper + Dictionary")
    }

    func testToolLabelBothWhenHarperAndModelContribute() {
        let label = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "Teh corrected text",
            originalText: "Teh incorect text",
            modelCorrectedText: "The corrected text"
        )
        XCTAssertEqual(label, "Harper + Local Model")
    }

    func testToolLabelNilWhenNothingChanged() {
        let label = CorrectionPipelineSupport.toolLabel(
            spellFixedText: "Same text",
            originalText: "Same text",
            modelCorrectedText: "Same text"
        )
        XCTAssertNil(label)
    }

    // MARK: - AX verification fallback logic

    func testAXVerificationNilReadbackTreatedAsSuccess() {
        XCTAssertFalse(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: nil, correctedText: "Hello"
        ))
    }

    func testAXVerificationMismatchFallsToClipboard() {
        XCTAssertTrue(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: "Wrong text", correctedText: "Hello"
        ))
    }

    // MARK: - Sentinel detection

    func testSentinelDetectedOnClipboard() {
        let sentinel = "__GHOSTEDIT_SENTINEL_abc123__"
        XCTAssertTrue(CorrectionPipelineSupport.isSentinelValue(sentinel, sentinel: sentinel))
        XCTAssertTrue(CorrectionPipelineSupport.isSentinelValue("  \n  ", sentinel: sentinel))
        XCTAssertFalse(CorrectionPipelineSupport.isSentinelValue("Real user text", sentinel: sentinel))
    }

    // MARK: - Full pipeline scenario

    func testFullPipelineScenarioTextEditCorrection() {
        // 1. Resolve target
        let target = CorrectionPipelineSupport.resolveTarget(
            frontmostBundleID: "com.apple.TextEdit",
            ownBundleID: "com.ghostedit.app",
            cachedAppIsAvailable: false,
            cachedAppIsTerminated: false
        )
        XCTAssertEqual(target, .frontmost)

        // 2. Determine text capture
        let captureStrategy = CorrectionPipelineSupport.textCaptureStrategy(
            axSelectedText: "Teh quick brown fox",
            axFullText: nil,
            axCursorPosition: nil,
            lineExtractionResult: false,
            containsObjectReplacement: false
        )
        XCTAssertEqual(captureStrategy, .accessibilitySelectedText)

        // 3. Protect tokens
        let text = "Teh quick brown fox jumps over https://example.com"
        let protection = TokenPreservationSupport.protectTokens(in: text)

        // 4. Simulated correction
        let corrected = protection.protectedText.replacingOccurrences(of: "Teh", with: "The")
        let restored = TokenPreservationSupport.restoreTokens(in: corrected, tokens: protection.tokens)
        XCTAssertTrue(restored.contains("https://example.com"))
        XCTAssertTrue(restored.hasPrefix("The quick"))

        // 5. Determine write-back strategy
        let writeBack = CorrectionPipelineSupport.selectWriteBackStrategy(
            hasLineContext: false,
            lineWriteBackSucceeded: nil,
            axReplacementSucceeded: true,
            axVerified: true,
            clipboardOnly: false
        )
        XCTAssertEqual(writeBack, .axReplacement)

        // 6. Verify AX read-back
        XCTAssertFalse(CorrectionPipelineSupport.shouldFallbackToClipboard(
            readBackText: restored, correctedText: restored
        ))
    }
}
