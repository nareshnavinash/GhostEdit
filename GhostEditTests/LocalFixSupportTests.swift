import XCTest
@testable import GhostEditCore

final class LocalFixSupportTests: XCTestCase {

    // MARK: - extractLineAtCursor

    func testExtractLineAtCursor_middleLine() {
        let text = "first line\nsecond line\nthird line"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 15)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "second line")
        XCTAssertEqual(result?.lineRange, NSRange(location: 11, length: 12))
    }

    func testExtractLineAtCursor_firstLine() {
        let text = "hello world\nsecond"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 3)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "hello world")
    }

    func testExtractLineAtCursor_lastLineNoNewline() {
        let text = "first\nlast"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 8)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "last")
        XCTAssertEqual(result?.lineRange, NSRange(location: 6, length: 4))
    }

    func testExtractLineAtCursor_cursorBeyondLength() {
        let text = "single line"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 999)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "single line")
    }

    func testExtractLineAtCursor_cursorNegative() {
        let text = "first\nsecond"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: -5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "first")
    }

    func testExtractLineAtCursor_emptyLine() {
        let text = "first\n\nthird"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 6)
        XCTAssertNil(result)
    }

    func testExtractLineAtCursor_whitespaceOnlyLine() {
        let text = "first\n   \nthird"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 7)
        XCTAssertNil(result)
    }

    func testExtractLineAtCursor_emptyText() {
        let result = LocalFixSupport.extractLineAtCursor(text: "", cursorLocation: 0)
        XCTAssertNil(result)
    }

    func testExtractLineAtCursor_singleLineNoCursor() {
        let text = "only line"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "only line")
        XCTAssertEqual(result?.lineRange, NSRange(location: 0, length: 9))
    }

    func testExtractLineAtCursor_cursorAtNewline() {
        let text = "first\nsecond\nthird"
        // cursor at position 5 (the \n) should return "first" line
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "first")
    }

    func testExtractLineAtCursor_trailingNewlineStripped() {
        let text = "hello\nworld\n"
        let result = LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineText, "hello")
        // lineRange should include the trailing newline
        XCTAssertEqual(result?.lineRange, NSRange(location: 0, length: 6))
    }

    // MARK: - mergeIssues

    func testMergeIssues_noOverlap() {
        let harper = [
            SpellCheckIssue(word: "tset", range: NSRange(location: 0, length: 4), kind: .spelling, suggestions: ["test"])
        ]
        let nsChecker = [
            SpellCheckIssue(word: "chk", range: NSRange(location: 10, length: 3), kind: .spelling, suggestions: ["check"])
        ]
        let result = LocalFixSupport.mergeIssues(harper: harper, nsChecker: nsChecker, text: "tset text chk")
        // Both should be present (subject to filter/truncate)
        XCTAssertTrue(result.count >= 1)
    }

    func testMergeIssues_withOverlap() {
        let harper = [
            SpellCheckIssue(word: "testt", range: NSRange(location: 0, length: 5), kind: .spelling, suggestions: ["test"])
        ]
        let nsChecker = [
            SpellCheckIssue(word: "stte", range: NSRange(location: 3, length: 4), kind: .spelling, suggestions: ["site"])
        ]
        let result = LocalFixSupport.mergeIssues(harper: harper, nsChecker: nsChecker, text: "testt text")
        // NS issue overlaps harper issue, so only harper should remain
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.word, "testt")
    }

    func testMergeIssues_emptyInputs() {
        let result = LocalFixSupport.mergeIssues(harper: [], nsChecker: [], text: "hello")
        XCTAssertTrue(result.isEmpty)
    }

    func testMergeIssues_onlyHarper() {
        let harper = [
            SpellCheckIssue(word: "tset", range: NSRange(location: 0, length: 4), kind: .grammar, suggestions: ["test"])
        ]
        let result = LocalFixSupport.mergeIssues(harper: harper, nsChecker: [], text: "tset text")
        XCTAssertEqual(result.count, 1)
    }

    func testMergeIssues_onlyNSChecker() {
        let nsChecker = [
            SpellCheckIssue(word: "tset", range: NSRange(location: 0, length: 4), kind: .grammar, suggestions: ["test"])
        ]
        let result = LocalFixSupport.mergeIssues(harper: [], nsChecker: nsChecker, text: "tset text")
        XCTAssertEqual(result.count, 1)
    }
}
