import XCTest
@testable import GhostEditCore

final class PartialCorrectionSupportTests: XCTestCase {
    // MARK: - splitIntoSentences

    func testSplitEmptyString() {
        let parts = PartialCorrectionSupport.splitIntoSentences("")
        XCTAssertTrue(parts.isEmpty)
    }

    func testSplitSingleSentence() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Hello world.")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].sentence, "Hello world.")
        XCTAssertEqual(parts[0].trailing, "")
    }

    func testSplitTwoSentences() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Hello. World.")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].sentence, "Hello.")
        XCTAssertEqual(parts[0].trailing, " ")
        XCTAssertEqual(parts[1].sentence, "World.")
        XCTAssertEqual(parts[1].trailing, "")
    }

    func testSplitPreservesMultipleSpaces() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Hello.  World.")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].trailing, "  ")
    }

    func testSplitExclamationAndQuestion() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Wow! Really? Yes.")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0].sentence, "Wow!")
        XCTAssertEqual(parts[1].sentence, "Really?")
        XCTAssertEqual(parts[2].sentence, "Yes.")
    }

    func testSplitNoTerminator() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Hello world")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].sentence, "Hello world")
    }

    func testSplitWithNewlines() {
        let parts = PartialCorrectionSupport.splitIntoSentences("First.\nSecond.")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].trailing, "\n")
    }

    func testSplitTrailingWhitespaceOnly() {
        let parts = PartialCorrectionSupport.splitIntoSentences("Hello.  ")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].sentence, "Hello.")
        XCTAssertEqual(parts[0].trailing, "  ")
    }

    // MARK: - reassemble

    func testReassembleEmpty() {
        let result = PartialCorrectionSupport.reassemble([])
        XCTAssertEqual(result, "")
    }

    func testReassembleRoundTrip() {
        let original = "Hello. World! How? Fine."
        let parts = PartialCorrectionSupport.splitIntoSentences(original)
        let reassembled = PartialCorrectionSupport.reassemble(parts)
        XCTAssertEqual(reassembled, original)
    }

    func testReassemblePreservesSpacing() {
        let original = "First.  Second.\nThird."
        let parts = PartialCorrectionSupport.splitIntoSentences(original)
        let reassembled = PartialCorrectionSupport.reassemble(parts)
        XCTAssertEqual(reassembled, original)
    }

    // MARK: - sentenceNeedsCorrection

    func testSentenceNeedsCorrectionIdentical() {
        XCTAssertFalse(PartialCorrectionSupport.sentenceNeedsCorrection(
            original: "Hello.", corrected: "Hello."
        ))
    }

    func testSentenceNeedsCorrectionDifferent() {
        XCTAssertTrue(PartialCorrectionSupport.sentenceNeedsCorrection(
            original: "hello", corrected: "Hello."
        ))
    }

    func testSentenceNeedsCorrectionIgnoresWhitespace() {
        XCTAssertFalse(PartialCorrectionSupport.sentenceNeedsCorrection(
            original: "  Hello.  ", corrected: "Hello."
        ))
    }
}
