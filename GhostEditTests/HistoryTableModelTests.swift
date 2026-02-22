import XCTest
@testable import GhostEditCore

final class HistoryTableModelTests: XCTestCase {
    func testRowInitializerFormatsSuccessfulEntry() {
        let entry = makeEntry(
            index: 1,
            provider: "Claude",
            model: "haiku",
            durationMilliseconds: 420,
            succeeded: true
        )

        let row = HistoryTableRow(entry: entry) { _ in "2026-02-22 12:30:00" }

        XCTAssertEqual(row.timestamp, "2026-02-22 12:30:00")
        XCTAssertEqual(row.status, "Succeeded")
        XCTAssertEqual(row.provider, "Claude")
        XCTAssertEqual(row.model, "haiku")
        XCTAssertEqual(row.duration, "420 ms")
        XCTAssertEqual(row.original, "original-1")
        XCTAssertEqual(row.generated, "generated-1")
    }

    func testRowInitializerFormatsFailedEntry() {
        let entry = makeEntry(
            index: 2,
            provider: "Gemini",
            model: "gemini-2.5-flash-lite",
            durationMilliseconds: 0,
            succeeded: false
        )

        let row = HistoryTableRow(entry: entry) { _ in "time" }

        XCTAssertEqual(row.status, "Failed")
        XCTAssertEqual(row.duration, "0 ms")
        XCTAssertEqual(row.provider, "Gemini")
        XCTAssertEqual(row.model, "gemini-2.5-flash-lite")
    }

    func testValueReturnsExpectedFieldForEveryColumn() {
        let entry = makeEntry(
            index: 3,
            provider: "Codex",
            model: "gpt-5-codex",
            durationMilliseconds: 7,
            succeeded: true
        )
        let row = HistoryTableRow(entry: entry) { _ in "stamp" }

        XCTAssertEqual(row.value(for: .timestamp), "stamp")
        XCTAssertEqual(row.value(for: .status), "Succeeded")
        XCTAssertEqual(row.value(for: .provider), "Codex")
        XCTAssertEqual(row.value(for: .model), "gpt-5-codex")
        XCTAssertEqual(row.value(for: .duration), "7 ms")
        XCTAssertEqual(row.value(for: .original), "original-3")
        XCTAssertEqual(row.value(for: .generated), "generated-3")
    }

    func testRowsMapsEntriesInOrderAndSupportsEmptyInput() {
        let first = makeEntry(
            index: 10,
            provider: "Claude",
            model: "haiku",
            durationMilliseconds: 11,
            succeeded: true
        )
        let second = makeEntry(
            index: 11,
            provider: "Codex",
            model: "gpt-5-codex",
            durationMilliseconds: 22,
            succeeded: false
        )

        var rows = HistoryTableModel.rows(from: [], timestampFormatter: { _ in "unused" })
        XCTAssertEqual(rows, [])

        rows = HistoryTableModel.rows(from: [first, second]) { date in
            "t-\(Int(date.timeIntervalSince1970))"
        }

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].timestamp, "t-\(Int(first.timestamp.timeIntervalSince1970))")
        XCTAssertEqual(rows[0].provider, "Claude")
        XCTAssertEqual(rows[1].status, "Failed")
        XCTAssertEqual(rows[1].provider, "Codex")
    }

    private func makeEntry(
        index: Int,
        provider: String,
        model: String,
        durationMilliseconds: Int,
        succeeded: Bool
    ) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
            originalText: "original-\(index)",
            generatedText: "generated-\(index)",
            provider: provider,
            model: model,
            durationMilliseconds: durationMilliseconds,
            succeeded: succeeded
        )
    }
}
