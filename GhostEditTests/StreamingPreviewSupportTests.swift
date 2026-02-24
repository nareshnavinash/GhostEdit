import XCTest
@testable import GhostEditCore

final class StreamingPreviewSupportTests: XCTestCase {
    func testStyledSegmentsFromDiff() {
        let diff: [DiffSegment] = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "wrold"),
            DiffSegment(kind: .insertion, text: "world"),
        ]
        let styled = StreamingPreviewSupport.styledSegments(from: diff)
        XCTAssertEqual(styled.count, 3)
        XCTAssertEqual(styled[0], StreamingPreviewSupport.StyledSegment(text: "Hello ", kind: .unchanged))
        XCTAssertEqual(styled[1], StreamingPreviewSupport.StyledSegment(text: "wrold", kind: .removed))
        XCTAssertEqual(styled[2], StreamingPreviewSupport.StyledSegment(text: "world", kind: .added))
    }

    func testCorrectedTextExcludesDeletions() {
        let diff: [DiffSegment] = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "wrold"),
            DiffSegment(kind: .insertion, text: "world"),
            DiffSegment(kind: .equal, text: "!"),
        ]
        let result = StreamingPreviewSupport.correctedText(from: diff)
        XCTAssertEqual(result, "Hello world!")
    }

    func testStreamingStatus() {
        XCTAssertEqual(
            StreamingPreviewSupport.streamingStatus(charCount: 42),
            "Receiving... (42 chars)"
        )
    }

    func testCompletedStatusNoChanges() {
        XCTAssertEqual(
            StreamingPreviewSupport.completedStatus(changeCount: 0),
            "No changes detected — press R to regenerate, Esc to cancel"
        )
    }

    func testCompletedStatusSingular() {
        XCTAssertEqual(
            StreamingPreviewSupport.completedStatus(changeCount: 1),
            "1 change — Tab to accept, R to regenerate, Esc to cancel"
        )
    }

    func testCompletedStatusPlural() {
        XCTAssertEqual(
            StreamingPreviewSupport.completedStatus(changeCount: 5),
            "5 changes — Tab to accept, R to regenerate, Esc to cancel"
        )
    }

    func testChangeCount() {
        let diff: [DiffSegment] = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "wrold"),
            DiffSegment(kind: .insertion, text: "world"),
        ]
        XCTAssertEqual(StreamingPreviewSupport.changeCount(from: diff), 2)
    }

    func testChangeCountAllEqual() {
        let diff: [DiffSegment] = [
            DiffSegment(kind: .equal, text: "No changes"),
        ]
        XCTAssertEqual(StreamingPreviewSupport.changeCount(from: diff), 0)
    }

    func testStyledSegmentsEmpty() {
        let styled = StreamingPreviewSupport.styledSegments(from: [])
        XCTAssertTrue(styled.isEmpty)
    }

    func testCorrectedTextEmpty() {
        let result = StreamingPreviewSupport.correctedText(from: [])
        XCTAssertEqual(result, "")
    }

    func testCorrectedTextOnlyDeletions() {
        let diff: [DiffSegment] = [
            DiffSegment(kind: .deletion, text: "removed"),
        ]
        let result = StreamingPreviewSupport.correctedText(from: diff)
        XCTAssertEqual(result, "")
    }
}
