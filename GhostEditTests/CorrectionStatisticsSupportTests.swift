import XCTest
@testable import GhostEditCore

final class CorrectionStatisticsSupportTests: XCTestCase {
    func testComputeFromEmptyEntries() {
        let stats = CorrectionStatisticsSupport.compute(from: [])
        XCTAssertEqual(stats.totalCorrections, 0)
        XCTAssertEqual(stats.successCount, 0)
        XCTAssertEqual(stats.failureCount, 0)
        XCTAssertEqual(stats.averageDurationMilliseconds, 0)
        XCTAssertEqual(stats.totalCharactersCorrected, 0)
        XCTAssertEqual(stats.longestCorrectionCharacters, 0)
        XCTAssertEqual(stats.providerBreakdown, [:])
        XCTAssertEqual(stats.modelBreakdown, [:])
        XCTAssertEqual(stats.successRate, 0)
    }

    func testComputeFromSingleSuccessfulEntry() {
        let entry = makeEntry(original: "hello world", succeeded: true, duration: 500, provider: "Claude", model: "haiku")
        let stats = CorrectionStatisticsSupport.compute(from: [entry])

        XCTAssertEqual(stats.totalCorrections, 1)
        XCTAssertEqual(stats.successCount, 1)
        XCTAssertEqual(stats.failureCount, 0)
        XCTAssertEqual(stats.averageDurationMilliseconds, 500)
        XCTAssertEqual(stats.totalCharactersCorrected, 11)
        XCTAssertEqual(stats.longestCorrectionCharacters, 11)
        XCTAssertEqual(stats.providerBreakdown, ["Claude": 1])
        XCTAssertEqual(stats.modelBreakdown, ["haiku": 1])
        XCTAssertEqual(stats.successRate, 1.0)
    }

    func testComputeFromMixedEntries() {
        let entries = [
            makeEntry(original: "short", succeeded: true, duration: 200, provider: "Claude", model: "haiku"),
            makeEntry(original: "medium text here", succeeded: true, duration: 800, provider: "Claude", model: "sonnet"),
            makeEntry(original: "fail", succeeded: false, duration: 100, provider: "Gemini", model: "flash"),
        ]
        let stats = CorrectionStatisticsSupport.compute(from: entries)

        XCTAssertEqual(stats.totalCorrections, 3)
        XCTAssertEqual(stats.successCount, 2)
        XCTAssertEqual(stats.failureCount, 1)
        XCTAssertEqual(stats.averageDurationMilliseconds, 366) // (200+800+100)/3
        XCTAssertEqual(stats.totalCharactersCorrected, 21) // 5 + 16
        XCTAssertEqual(stats.longestCorrectionCharacters, 16)
        XCTAssertEqual(stats.providerBreakdown, ["Claude": 2, "Gemini": 1])
        XCTAssertEqual(stats.modelBreakdown, ["haiku": 1, "sonnet": 1, "flash": 1])
        XCTAssertEqual(stats.successRate, 2.0 / 3.0, accuracy: 0.001)
    }

    func testComputeAllFailed() {
        let entries = [
            makeEntry(original: "a", succeeded: false, duration: 100, provider: "Claude", model: "haiku"),
            makeEntry(original: "b", succeeded: false, duration: 200, provider: "Claude", model: "haiku"),
        ]
        let stats = CorrectionStatisticsSupport.compute(from: entries)

        XCTAssertEqual(stats.successCount, 0)
        XCTAssertEqual(stats.failureCount, 2)
        XCTAssertEqual(stats.totalCharactersCorrected, 0)
        XCTAssertEqual(stats.longestCorrectionCharacters, 0)
        XCTAssertEqual(stats.successRate, 0)
    }

    func testAverageDurationFormattedMilliseconds() {
        let entry = makeEntry(original: "x", succeeded: true, duration: 500, provider: "P", model: "M")
        let stats = CorrectionStatisticsSupport.compute(from: [entry])
        XCTAssertEqual(stats.averageDurationFormatted, "500ms")
    }

    func testAverageDurationFormattedSeconds() {
        let entry = makeEntry(original: "x", succeeded: true, duration: 2500, provider: "P", model: "M")
        let stats = CorrectionStatisticsSupport.compute(from: [entry])
        XCTAssertEqual(stats.averageDurationFormatted, "2.5s")
    }

    func testFormattedSummaryContainsKeyFields() {
        let entries = [
            makeEntry(original: "hello", succeeded: true, duration: 500, provider: "Claude", model: "haiku"),
        ]
        let stats = CorrectionStatisticsSupport.compute(from: entries)
        let summary = CorrectionStatisticsSupport.formattedSummary(stats)

        XCTAssertTrue(summary.contains("Total corrections: 1"))
        XCTAssertTrue(summary.contains("Successful: 1"))
        XCTAssertTrue(summary.contains("Failed: 0"))
        XCTAssertTrue(summary.contains("Success rate: 100%"))
        XCTAssertTrue(summary.contains("Average duration: 500ms"))
        XCTAssertTrue(summary.contains("Claude: 1"))
        XCTAssertTrue(summary.contains("haiku: 1"))
    }

    func testFormattedSummaryEmptyEntries() {
        let stats = CorrectionStatisticsSupport.compute(from: [])
        let summary = CorrectionStatisticsSupport.formattedSummary(stats)
        XCTAssertTrue(summary.contains("Total corrections: 0"))
        XCTAssertTrue(summary.contains("Success rate: 0%"))
    }

    func testSortedBreakdownReturnsSortedByValueDescending() {
        let breakdown = ["A": 5, "B": 10, "C": 1]
        let sorted = CorrectionStatisticsSupport.sortedBreakdown(breakdown)
        XCTAssertEqual(sorted.map(\.key), ["B", "A", "C"])
        XCTAssertEqual(sorted.map(\.value), [10, 5, 1])
    }

    func testSortedBreakdownEmptyReturnsEmpty() {
        let sorted = CorrectionStatisticsSupport.sortedBreakdown([:])
        XCTAssertTrue(sorted.isEmpty)
    }

    func testFormattedSummaryPartialSuccessRate() {
        let entries = [
            makeEntry(original: "a", succeeded: true, duration: 100, provider: "P", model: "M"),
            makeEntry(original: "b", succeeded: false, duration: 100, provider: "P", model: "M"),
            makeEntry(original: "c", succeeded: true, duration: 100, provider: "P", model: "M"),
        ]
        let stats = CorrectionStatisticsSupport.compute(from: entries)
        let summary = CorrectionStatisticsSupport.formattedSummary(stats)
        XCTAssertTrue(summary.contains("Success rate: 66.7%"))
    }

    private func makeEntry(
        original: String,
        succeeded: Bool,
        duration: Int,
        provider: String,
        model: String
    ) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            originalText: original,
            generatedText: succeeded ? "corrected-\(original)" : "",
            provider: provider,
            model: model,
            durationMilliseconds: duration,
            succeeded: succeeded
        )
    }
}
