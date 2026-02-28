import XCTest
@testable import GhostEditCore

final class HistoryFilterSupportTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(succeeded: Bool, durationMilliseconds: Int = 500) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            originalText: "original",
            generatedText: "corrected",
            provider: "claude",
            model: "claude-3",
            durationMilliseconds: durationMilliseconds,
            succeeded: succeeded
        )
    }

    // MARK: - applyStatusFilter

    func testStatusFilterAll() {
        let entries = [makeEntry(succeeded: true), makeEntry(succeeded: false), makeEntry(succeeded: true)]
        let result = HistoryFilterSupport.applyStatusFilter(entries, filter: 0)
        XCTAssertEqual(result.count, 3)
    }

    func testStatusFilterSuccess() {
        let entries = [makeEntry(succeeded: true), makeEntry(succeeded: false), makeEntry(succeeded: true)]
        let result = HistoryFilterSupport.applyStatusFilter(entries, filter: 1)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.succeeded })
    }

    func testStatusFilterFailed() {
        let entries = [makeEntry(succeeded: true), makeEntry(succeeded: false), makeEntry(succeeded: true)]
        let result = HistoryFilterSupport.applyStatusFilter(entries, filter: 2)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.allSatisfy { !$0.succeeded })
    }

    func testStatusFilterUnknownValueReturnsAll() {
        let entries = [makeEntry(succeeded: true), makeEntry(succeeded: false)]
        let result = HistoryFilterSupport.applyStatusFilter(entries, filter: 99)
        XCTAssertEqual(result.count, 2)
    }

    func testStatusFilterEmptyArray() {
        let result = HistoryFilterSupport.applyStatusFilter([], filter: 1)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - applySearchFilter

    private func makeSearchItem(
        original: String = "",
        generated: String = "",
        provider: String = "",
        model: String = ""
    ) -> (entry: CorrectionHistoryEntry, original: String, generated: String, provider: String, model: String) {
        (entry: makeEntry(succeeded: true), original: original, generated: generated, provider: provider, model: model)
    }

    func testSearchFilterEmptyQuery() {
        let items = [makeSearchItem(original: "Hello")]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterMatchesOriginal() {
        let items = [
            makeSearchItem(original: "Hello world"),
            makeSearchItem(original: "Goodbye")
        ]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "hello")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterMatchesGenerated() {
        let items = [
            makeSearchItem(generated: "Fixed text here"),
            makeSearchItem(generated: "Other")
        ]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "fixed")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterMatchesProvider() {
        let items = [
            makeSearchItem(provider: "Claude"),
            makeSearchItem(provider: "Gemini")
        ]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "gemini")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterMatchesModel() {
        let items = [
            makeSearchItem(model: "claude-3-opus"),
            makeSearchItem(model: "gpt-4")
        ]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "opus")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterCaseInsensitive() {
        let items = [makeSearchItem(original: "Hello World")]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "HELLO")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchFilterNoMatch() {
        let items = [makeSearchItem(original: "Hello", generated: "World")]
        let result = HistoryFilterSupport.applySearchFilter(items, query: "xyz")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - relativeTimestamp

    private let stubTimeFormatter: (Date) -> String = { _ in "10:30 AM" }
    private let stubFullFormatter: (Date) -> String = { _ in "Jan 15, 2024" }

    func testRelativeTimestampJustNow() {
        let now = Date()
        let date = now.addingTimeInterval(-30)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "Just now")
    }

    func testRelativeTimestamp1MinAgo() {
        let now = Date()
        let date = now.addingTimeInterval(-60)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "1 min ago")
    }

    func testRelativeTimestamp5MinsAgo() {
        let now = Date()
        let date = now.addingTimeInterval(-300)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "5 mins ago")
    }

    func testRelativeTimestamp1HourAgo() {
        let now = Date()
        let date = now.addingTimeInterval(-3600)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "1 hour ago")
    }

    func testRelativeTimestamp3HoursAgo() {
        let now = Date()
        let date = now.addingTimeInterval(-10800)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "3 hours ago")
    }

    func testRelativeTimestampYesterday() {
        let now = Date()
        let date = now.addingTimeInterval(-90000) // 25 hours
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "Yesterday at 10:30 AM")
    }

    func testRelativeTimestampOlder() {
        let now = Date()
        let date = now.addingTimeInterval(-200000) // > 2 days
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "Jan 15, 2024")
    }

    func testRelativeTimestampBoundary59Seconds() {
        let now = Date()
        let date = now.addingTimeInterval(-59)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "Just now")
    }

    func testRelativeTimestampBoundary59Minutes() {
        let now = Date()
        let date = now.addingTimeInterval(-3599)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "59 mins ago")
    }

    func testRelativeTimestampBoundary23Hours() {
        let now = Date()
        let date = now.addingTimeInterval(-82800)
        let result = HistoryFilterSupport.relativeTimestamp(
            for: date, now: now,
            timeOnlyFormatter: stubTimeFormatter, fullFormatter: stubFullFormatter
        )
        XCTAssertEqual(result, "23 hours ago")
    }

    // MARK: - durationColorName

    func testDurationFastGreen() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 500), "systemGreen")
    }

    func testDurationBoundaryGreen() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 1999), "systemGreen")
    }

    func testDurationMediumOrange() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 2000), "systemOrange")
    }

    func testDurationBoundaryOrange() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 4999), "systemOrange")
    }

    func testDurationSlowRed() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 5000), "systemRed")
    }

    func testDurationVerySlowRed() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 10000), "systemRed")
    }

    func testDurationZeroGreen() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 0), "systemGreen")
    }
}
