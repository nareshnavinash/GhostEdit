import XCTest
@testable import GhostEditCore

final class DiffSupportTests: XCTestCase {
    // MARK: - Tokenization

    func testTokenizeEmptyString() {
        XCTAssertEqual(DiffSupport.tokenize(""), [])
    }

    func testTokenizeSingleWord() {
        XCTAssertEqual(DiffSupport.tokenize("hello"), ["hello"])
    }

    func testTokenizePreservesWhitespace() {
        let tokens = DiffSupport.tokenize("hello world")
        XCTAssertEqual(tokens, ["hello", " ", "world"])
    }

    func testTokenizeMultipleSpaces() {
        let tokens = DiffSupport.tokenize("a  b")
        XCTAssertEqual(tokens, ["a", "  ", "b"])
    }

    func testTokenizeLeadingTrailingWhitespace() {
        let tokens = DiffSupport.tokenize(" hi ")
        XCTAssertEqual(tokens, [" ", "hi", " "])
    }

    func testTokenizeNewlines() {
        let tokens = DiffSupport.tokenize("a\nb")
        XCTAssertEqual(tokens, ["a", "\n", "b"])
    }

    // MARK: - isIdentical

    func testIsIdenticalReturnsTrueForSameText() {
        XCTAssertTrue(DiffSupport.isIdentical(old: "hello", new: "hello"))
    }

    func testIsIdenticalReturnsTrueWithDifferentWhitespace() {
        XCTAssertTrue(DiffSupport.isIdentical(old: "  hello\n", new: "hello"))
    }

    func testIsIdenticalReturnsFalseForDifferentText() {
        XCTAssertFalse(DiffSupport.isIdentical(old: "hello", new: "world"))
    }

    // MARK: - wordDiff

    func testWordDiffBothEmpty() {
        let segments = DiffSupport.wordDiff(old: "", new: "")
        XCTAssertEqual(segments, [])
    }

    func testWordDiffIdenticalText() {
        let segments = DiffSupport.wordDiff(old: "hello world", new: "hello world")
        XCTAssertEqual(segments, [DiffSegment(kind: .equal, text: "hello world")])
    }

    func testWordDiffInsertionOnly() {
        let segments = DiffSupport.wordDiff(old: "", new: "hello")
        XCTAssertEqual(segments, [DiffSegment(kind: .insertion, text: "hello")])
    }

    func testWordDiffDeletionOnly() {
        let segments = DiffSupport.wordDiff(old: "hello", new: "")
        XCTAssertEqual(segments, [DiffSegment(kind: .deletion, text: "hello")])
    }

    func testWordDiffSingleWordChange() {
        let segments = DiffSupport.wordDiff(old: "hello world", new: "hello there")

        // Verify reconstruction: deletions+equals = old, insertions+equals = new
        let reconstructedOld = segments.filter { $0.kind != .insertion }.map(\.text).joined()
        let reconstructedNew = segments.filter { $0.kind != .deletion }.map(\.text).joined()
        XCTAssertEqual(reconstructedOld, "hello world")
        XCTAssertEqual(reconstructedNew, "hello there")

        // "hello" and " " should be equal; "world"/"there" differ
        XCTAssertTrue(segments.contains(where: { $0.kind == .deletion }))
        XCTAssertTrue(segments.contains(where: { $0.kind == .insertion }))
    }

    func testWordDiffMiddleInsertion() {
        let segments = DiffSupport.wordDiff(
            old: "the cat sat",
            new: "the big cat sat"
        )

        let reconstructedOld = segments.filter { $0.kind != .insertion }.map(\.text).joined()
        let reconstructedNew = segments.filter { $0.kind != .deletion }.map(\.text).joined()
        XCTAssertEqual(reconstructedOld, "the cat sat")
        XCTAssertEqual(reconstructedNew, "the big cat sat")
        XCTAssertTrue(segments.contains(where: { $0.kind == .insertion }))
    }

    func testWordDiffMiddleDeletion() {
        let segments = DiffSupport.wordDiff(
            old: "the big cat sat",
            new: "the cat sat"
        )

        let reconstructedOld = segments.filter { $0.kind != .insertion }.map(\.text).joined()
        let reconstructedNew = segments.filter { $0.kind != .deletion }.map(\.text).joined()
        XCTAssertEqual(reconstructedOld, "the big cat sat")
        XCTAssertEqual(reconstructedNew, "the cat sat")
        XCTAssertTrue(segments.contains(where: { $0.kind == .deletion }))
    }

    // MARK: - changeSummary

    func testChangeSummaryNoChanges() {
        let segments = [DiffSegment(kind: .equal, text: "hello world")]
        XCTAssertEqual(DiffSupport.changeSummary(segments: segments), "No changes")
    }

    func testChangeSummaryAdditionsOnly() {
        let segments = [
            DiffSegment(kind: .equal, text: "hello "),
            DiffSegment(kind: .insertion, text: "beautiful "),
            DiffSegment(kind: .equal, text: "world")
        ]
        XCTAssertEqual(DiffSupport.changeSummary(segments: segments), "1 word added")
    }

    func testChangeSummaryRemovalsOnly() {
        let segments = [
            DiffSegment(kind: .equal, text: "hello "),
            DiffSegment(kind: .deletion, text: "big beautiful "),
            DiffSegment(kind: .equal, text: "world")
        ]
        XCTAssertEqual(DiffSupport.changeSummary(segments: segments), "2 words removed")
    }

    func testChangeSummaryMixed() {
        let segments = [
            DiffSegment(kind: .deletion, text: "bad"),
            DiffSegment(kind: .insertion, text: "good nice"),
            DiffSegment(kind: .equal, text: " day")
        ]
        XCTAssertEqual(DiffSupport.changeSummary(segments: segments), "2 words added, 1 word removed")
    }

    func testChangeSummaryEmpty() {
        XCTAssertEqual(DiffSupport.changeSummary(segments: []), "No changes")
    }

    // MARK: - Real-world grammar correction

    func testWordDiffGrammarCorrection() {
        let old = "I has went to the store yesterday"
        let new = "I had gone to the store yesterday"
        let segments = DiffSupport.wordDiff(old: old, new: new)

        // Verify there are changes
        XCTAssertTrue(segments.contains(where: { $0.kind == .deletion }))
        XCTAssertTrue(segments.contains(where: { $0.kind == .insertion }))
        XCTAssertTrue(segments.contains(where: { $0.kind == .equal }))

        // Reassemble should reproduce original and new text
        let deletionsAndEquals = segments
            .filter { $0.kind != .insertion }
            .map(\.text)
            .joined()
        XCTAssertEqual(deletionsAndEquals, old)

        let insertionsAndEquals = segments
            .filter { $0.kind != .deletion }
            .map(\.text)
            .joined()
        XCTAssertEqual(insertionsAndEquals, new)
    }

    // MARK: - charDiff

    func testCharDiffIdenticalStrings() {
        let segments = DiffSupport.charDiff(old: "hello", new: "hello")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.kind, .equal)
        XCTAssertEqual(segments.first?.text, "hello")
    }

    func testCharDiffSingleCharChange() {
        let segments = DiffSupport.charDiff(old: "cat", new: "car")
        // "ca" equal, "t" deleted, "r" inserted
        let deletions = segments.filter { $0.kind == .deletion }.map(\.text).joined()
        let insertions = segments.filter { $0.kind == .insertion }.map(\.text).joined()
        XCTAssertEqual(deletions, "t")
        XCTAssertEqual(insertions, "r")
    }

    func testCharDiffReconstructsOriginalAndNew() {
        let old = "The quick fox"
        let new = "The slow fox"
        let segments = DiffSupport.charDiff(old: old, new: new)

        let reconstructedOld = segments
            .filter { $0.kind != .insertion }
            .map(\.text)
            .joined()
        XCTAssertEqual(reconstructedOld, old)

        let reconstructedNew = segments
            .filter { $0.kind != .deletion }
            .map(\.text)
            .joined()
        XCTAssertEqual(reconstructedNew, new)
    }

    func testCharDiffEmptyStrings() {
        let segments = DiffSupport.charDiff(old: "", new: "")
        XCTAssertTrue(segments.isEmpty)
    }

    func testCharDiffInsertionOnly() {
        let segments = DiffSupport.charDiff(old: "", new: "abc")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.kind, .insertion)
        XCTAssertEqual(segments.first?.text, "abc")
    }
}
