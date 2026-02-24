import XCTest
@testable import GhostEditCore

final class CorrectionHistoryStoreTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for root in tempRoots {
            try? fileManager.removeItem(at: root)
        }
        tempRoots.removeAll()
        try super.tearDownWithError()
    }

    func testBootstrapCreatesHistoryFileAndIsIdempotent() throws {
        let (store, historyURL) = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertEqual(store.load(), [])

        try store.bootstrapIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertEqual(store.load(), [])

        try store.bootstrapIfNeeded()
        XCTAssertEqual(store.load(), [])
    }

    func testLoadReturnsEmptyWhenFileIsInvalidOrEmpty() throws {
        let (store, historyURL) = makeStore()
        try store.bootstrapIfNeeded()

        try "{}".write(to: historyURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load(), [])

        try Data().write(to: historyURL, options: .atomic)
        XCTAssertEqual(store.load(), [])
    }

    func testAppendTrimsToLimitAndPreservesNewestEntries() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        let first = makeEntry(index: 1)
        let second = makeEntry(index: 2)
        let third = makeEntry(index: 3)

        try store.append(first, limit: 2)
        try store.append(second, limit: 2)
        try store.append(third, limit: 2)

        let loaded = store.load()
        XCTAssertEqual(loaded, [second, third])
    }

    func testAppendAndTrimNormalizeLimitToMinimumOne() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        try store.append(makeEntry(index: 10), limit: 0)
        try store.append(makeEntry(index: 11), limit: 0)
        var loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].originalText, "original-11")

        try store.append(makeEntry(index: 12), limit: 3)
        try store.append(makeEntry(index: 13), limit: 3)
        loaded = store.load()
        XCTAssertEqual(loaded.count, 3)

        try store.trim(limit: 1)
        loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].originalText, "original-13")
    }

    func testLastSuccessfulEntryReturnsNilWhenEmpty() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        XCTAssertNil(store.lastSuccessfulEntry())
    }

    func testLastSuccessfulEntryReturnsNilWhenAllFailed() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        // makeEntry with odd index has succeeded: false
        try store.append(makeEntry(index: 1), limit: 100)
        try store.append(makeEntry(index: 3), limit: 100)

        XCTAssertNil(store.lastSuccessfulEntry())
    }

    func testLastSuccessfulEntryReturnsNewestSucceededEntry() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        // index 2 → succeeded: true
        // index 3 → succeeded: false
        // index 4 → succeeded: true
        try store.append(makeEntry(index: 2), limit: 100)
        try store.append(makeEntry(index: 3), limit: 100)
        try store.append(makeEntry(index: 4), limit: 100)

        let entry = store.lastSuccessfulEntry()
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.originalText, "original-4")
        XCTAssertTrue(entry?.succeeded == true)
    }

    func testLastSuccessfulEntrySkipsTrailingFailures() throws {
        let (store, _) = makeStore()
        try store.bootstrapIfNeeded()

        // index 2 → succeeded: true
        // index 5 → succeeded: false
        try store.append(makeEntry(index: 2), limit: 100)
        try store.append(makeEntry(index: 5), limit: 100)

        let entry = store.lastSuccessfulEntry()
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.originalText, "original-2")
    }

    private func makeStore() -> (CorrectionHistoryStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-history-tests-\(UUID().uuidString)", isDirectory: true)
        tempRoots.append(root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let historyURL = root.appendingPathComponent("history.json")
        return (CorrectionHistoryStore(fileURL: historyURL), historyURL)
    }

    private func makeEntry(index: Int) -> CorrectionHistoryEntry {
        CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
            originalText: "original-\(index)",
            generatedText: "generated-\(index)",
            provider: "Provider-\(index)",
            model: "model-\(index)",
            durationMilliseconds: index * 100,
            succeeded: index % 2 == 0
        )
    }
}
