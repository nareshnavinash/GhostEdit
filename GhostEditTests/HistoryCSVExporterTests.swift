import XCTest
@testable import GhostEditCore

final class HistoryCSVExporterTests: XCTestCase {
    func testCSVWithNoEntriesContainsHeaderAndTrailingNewline() {
        let csv = HistoryCSVExporter.csv(entries: []) { _ in "unused" }
        XCTAssertEqual(
            csv,
            "Timestamp,Status,Provider,Model,Duration (ms),Original Text,Generated Text\n"
        )
    }

    func testCSVSerializesRowsWithFormattedTimestampAndStatus() {
        let first = makeEntry(
            index: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_010),
            succeeded: true
        )
        let second = makeEntry(
            index: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_020),
            succeeded: false
        )

        let csv = HistoryCSVExporter.csv(entries: [first, second]) { date in
            "ts-\(Int(date.timeIntervalSince1970))"
        }

        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(
            lines[0],
            "Timestamp,Status,Provider,Model,Duration (ms),Original Text,Generated Text"
        )
        XCTAssertEqual(
            lines[1],
            "ts-1700000010,Succeeded,Provider-1,model-1,100,original-1,generated-1"
        )
        XCTAssertEqual(
            lines[2],
            "ts-1700000020,Failed,Provider-2,model-2,200,original-2,generated-2"
        )
        XCTAssertEqual(lines[3], "")
    }

    func testCSVEscapesCommaQuoteAndNewlineFields() {
        let entry = CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            originalText: "Hello,\n\"World\"",
            generatedText: "Line 1\r\nLine,2",
            provider: "Provider,One",
            model: "model-\"quoted\"",
            durationMilliseconds: 321,
            succeeded: true
        )

        let csv = HistoryCSVExporter.csv(entries: [entry]) { _ in "2026-02-22 14:00:00" }
        XCTAssertTrue(csv.contains("\"Provider,One\""))
        XCTAssertTrue(csv.contains("\"model-\"\"quoted\"\"\""))
        XCTAssertTrue(csv.contains("\"Hello,\n\"\"World\"\"\""))
        XCTAssertTrue(csv.contains("\"Line 1\r\nLine,2\""))
    }

    private func makeEntry(index: Int, timestamp: Date, succeeded: Bool) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: timestamp,
            originalText: "original-\(index)",
            generatedText: "generated-\(index)",
            provider: "Provider-\(index)",
            model: "model-\(index)",
            durationMilliseconds: index * 100,
            succeeded: succeeded
        )
    }
}
