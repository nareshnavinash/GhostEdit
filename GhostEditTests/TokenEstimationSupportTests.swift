import XCTest
@testable import GhostEditCore

final class TokenEstimationSupportTests: XCTestCase {
    func testEstimateTokensEmptyString() {
        XCTAssertEqual(TokenEstimationSupport.estimateTokens(for: ""), 0)
    }

    func testEstimateTokensShortString() {
        // "hi" = 2 chars → ceil(2/4) = 1 token
        XCTAssertEqual(TokenEstimationSupport.estimateTokens(for: "hi"), 1)
    }

    func testEstimateTokensLongerString() {
        // 12 chars → ceil(12/4) = 3 tokens
        XCTAssertEqual(TokenEstimationSupport.estimateTokens(for: "hello world!"), 3)
    }

    func testEstimateTokensMinimumOne() {
        XCTAssertGreaterThanOrEqual(TokenEstimationSupport.estimateTokens(for: "a"), 1)
    }

    func testEstimateCorrectionTokens() {
        let (input, output, total) = TokenEstimationSupport.estimateCorrectionTokens(
            systemPrompt: "Fix grammar",    // 11 chars → 3 tokens
            inputText: "hello world",        // 11 chars → 3 tokens
            outputText: "Hello, world."      // 13 chars → 4 tokens
        )
        XCTAssertEqual(input, 6)  // 3 + 3
        XCTAssertEqual(output, 4)
        XCTAssertEqual(total, 10)
    }

    func testEstimateCumulativeTokensFromEmptyEntries() {
        let (input, output, total) = TokenEstimationSupport.estimateCumulativeTokens(entries: [])
        XCTAssertEqual(input, 0)
        XCTAssertEqual(output, 0)
        XCTAssertEqual(total, 0)
    }

    func testEstimateCumulativeTokensSkipsFailedEntries() {
        let entries = [
            makeEntry(original: "hello", generated: "Hello.", succeeded: true),
            makeEntry(original: "fail", generated: "", succeeded: false),
        ]
        let (input, output, total) = TokenEstimationSupport.estimateCumulativeTokens(
            entries: entries,
            averagePromptLength: 8 // 8 chars → 2 tokens
        )
        // Only the successful entry counts:
        // prompt: 2 tokens + "hello": 2 tokens = 4 input
        // "Hello.": 2 tokens output
        XCTAssertEqual(input, 4)
        XCTAssertEqual(output, 2)
        XCTAssertEqual(total, 6)
    }

    func testEstimateCumulativeTokensMultipleEntries() {
        let entries = [
            makeEntry(original: "hello world", generated: "Hello, world.", succeeded: true),
            makeEntry(original: "test text", generated: "Test text.", succeeded: true),
        ]
        let result = TokenEstimationSupport.estimateCumulativeTokens(
            entries: entries,
            averagePromptLength: 200
        )
        XCTAssertGreaterThan(result.totalTokens, 0)
        XCTAssertEqual(result.totalTokens, result.inputTokens + result.outputTokens)
    }

    // MARK: - formatTokenCount

    func testFormatTokenCountSmall() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(42), "42")
    }

    func testFormatTokenCountThousands() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(1500), "1.5k")
    }

    func testFormatTokenCountMillions() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(2_500_000), "2.5M")
    }

    func testFormatTokenCountExactThousand() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(1000), "1.0k")
    }

    func testFormatTokenCountZero() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(0), "0")
    }

    func testFormatTokenCountJustUnderThousand() {
        XCTAssertEqual(TokenEstimationSupport.formatTokenCount(999), "999")
    }

    private func makeEntry(original: String, generated: String, succeeded: Bool) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            originalText: original,
            generatedText: generated,
            provider: "Claude",
            model: "haiku",
            durationMilliseconds: 500,
            succeeded: succeeded
        )
    }
}
