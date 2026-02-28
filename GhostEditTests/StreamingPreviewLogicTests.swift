import XCTest
@testable import GhostEditCore

final class StreamingPreviewLogicTests: XCTestCase {

    // MARK: - computeSimilarity

    func testSimilarityIdenticalStrings() {
        XCTAssertEqual(StreamingPreviewLogic.computeSimilarity(old: "Hello world", new: "Hello world"), 100)
    }

    func testSimilarityCompletelyDifferent() {
        XCTAssertEqual(StreamingPreviewLogic.computeSimilarity(old: "abc", new: "xyz"), 0)
    }

    func testSimilarityBothEmpty() {
        XCTAssertEqual(StreamingPreviewLogic.computeSimilarity(old: "", new: ""), 100)
    }

    func testSimilarityOneEmpty() {
        XCTAssertEqual(StreamingPreviewLogic.computeSimilarity(old: "Hello", new: ""), 0)
    }

    func testSimilarityPartialMatch() {
        let result = StreamingPreviewLogic.computeSimilarity(old: "Hello world", new: "Hello there")
        XCTAssertGreaterThan(result, 0)
        XCTAssertLessThan(result, 100)
    }

    // MARK: - buildChangeRanges

    func testBuildChangeRangesEmpty() {
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: [])
        XCTAssertTrue(ranges.isEmpty)
    }

    func testBuildChangeRangesEqualOnly() {
        let segments = [DiffSegment(kind: .equal, text: "Hello world")]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertTrue(ranges.isEmpty)
    }

    func testBuildChangeRangesDeletionOnly() {
        let segments = [DiffSegment(kind: .deletion, text: "deleted")]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].left.location, 0)
        XCTAssertEqual(ranges[0].left.length, "deleted".utf16.count)
        XCTAssertEqual(ranges[0].right.length, 0)
    }

    func testBuildChangeRangesInsertionOnly() {
        let segments = [DiffSegment(kind: .insertion, text: "inserted")]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].left.length, 0)
        XCTAssertEqual(ranges[0].right.location, 0)
        XCTAssertEqual(ranges[0].right.length, "inserted".utf16.count)
    }

    func testBuildChangeRangesDeletionInsertionMerge() {
        let segments = [
            DiffSegment(kind: .deletion, text: "old"),
            DiffSegment(kind: .insertion, text: "new")
        ]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].left.length, "old".utf16.count)
        XCTAssertEqual(ranges[0].right.length, "new".utf16.count)
    }

    func testBuildChangeRangesWithEqualBetween() {
        let segments = [
            DiffSegment(kind: .deletion, text: "old"),
            DiffSegment(kind: .equal, text: " same "),
            DiffSegment(kind: .insertion, text: "new")
        ]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 2)
    }

    func testBuildChangeRangesMultipleChanges() {
        let segments = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "bad"),
            DiffSegment(kind: .insertion, text: "good"),
            DiffSegment(kind: .equal, text: " text "),
            DiffSegment(kind: .deletion, text: "removed")
        ]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertGreaterThan(ranges[0].left.length, 0)
        XCTAssertGreaterThan(ranges[0].right.length, 0)
        XCTAssertGreaterThan(ranges[1].left.length, 0)
        XCTAssertEqual(ranges[1].right.length, 0)
    }

    // MARK: - navButtonStates

    func testNavButtonStatesNoChanges() {
        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 0, currentIndex: -1)
        XCTAssertFalse(prev)
        XCTAssertFalse(next)
    }

    func testNavButtonStatesAtFirst() {
        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 3, currentIndex: 0)
        XCTAssertFalse(prev)
        XCTAssertTrue(next)
    }

    func testNavButtonStatesAtMiddle() {
        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 3, currentIndex: 1)
        XCTAssertTrue(prev)
        XCTAssertTrue(next)
    }

    func testNavButtonStatesAtLast() {
        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 3, currentIndex: 2)
        XCTAssertTrue(prev)
        XCTAssertFalse(next)
    }

    func testNavButtonStatesSingleChange() {
        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 1, currentIndex: 0)
        XCTAssertFalse(prev)
        XCTAssertFalse(next)
    }

    // MARK: - canNavigatePrev / canNavigateNext

    func testCanNavigatePrevAtStart() {
        XCTAssertFalse(StreamingPreviewLogic.canNavigatePrev(currentIndex: 0))
    }

    func testCanNavigatePrevAtMiddle() {
        XCTAssertTrue(StreamingPreviewLogic.canNavigatePrev(currentIndex: 1))
    }

    func testCanNavigateNextAtEnd() {
        XCTAssertFalse(StreamingPreviewLogic.canNavigateNext(currentIndex: 2, totalChanges: 3))
    }

    func testCanNavigateNextAtMiddle() {
        XCTAssertTrue(StreamingPreviewLogic.canNavigateNext(currentIndex: 1, totalChanges: 3))
    }

    func testCanNavigateNextNoChanges() {
        XCTAssertFalse(StreamingPreviewLogic.canNavigateNext(currentIndex: -1, totalChanges: 0))
    }
}
