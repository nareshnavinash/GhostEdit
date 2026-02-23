import XCTest
import CoreGraphics
@testable import GhostEditCore

final class WritingCoachLayoutSupportTests: XCTestCase {
    func testCappedItemsReturnsAllWhenUnderLimit() {
        let items = ["A", "B", "C"]
        XCTAssertEqual(WritingCoachLayoutSupport.cappedItems(items), items)
    }

    func testCappedItemsTruncatesWhenOverLimit() {
        let items = ["1", "2", "3", "4", "5", "6", "7"]
        let result = WritingCoachLayoutSupport.cappedItems(items)
        XCTAssertEqual(result, ["1", "2", "3", "4", "5"])
    }

    func testCappedItemsReturnsEmptyForEmptyInput() {
        XCTAssertEqual(WritingCoachLayoutSupport.cappedItems([]), [])
    }

    func testCappedItemsRespectsZeroLimit() {
        XCTAssertEqual(WritingCoachLayoutSupport.cappedItems(["A", "B"], limit: 0), [])
    }

    func testCappedItemsRespectsNegativeLimit() {
        XCTAssertEqual(WritingCoachLayoutSupport.cappedItems(["A"], limit: -3), [])
    }

    func testCappedItemsRespectsCustomLimit() {
        let items = ["A", "B", "C", "D"]
        XCTAssertEqual(WritingCoachLayoutSupport.cappedItems(items, limit: 2), ["A", "B"])
    }

    func testPanelContentWidthCalculation() {
        let expected = (WritingCoachLayoutSupport.accessoryWidth - WritingCoachLayoutSupport.panelSpacing) / 2.0
            - (WritingCoachLayoutSupport.panelInset * 2)
        XCTAssertEqual(WritingCoachLayoutSupport.panelContentWidth(), expected)
    }

    func testPanelContentWidthIsPositive() {
        XCTAssertGreaterThan(WritingCoachLayoutSupport.panelContentWidth(), 0)
    }

    func testReviewedTextSingular() {
        XCTAssertEqual(WritingCoachLayoutSupport.reviewedText(sampleCount: 1), "Reviewed 1 writing sample(s).")
    }

    func testReviewedTextPlural() {
        XCTAssertEqual(WritingCoachLayoutSupport.reviewedText(sampleCount: 5), "Reviewed 5 writing sample(s).")
    }

    func testConstantsAreReasonable() {
        XCTAssertGreaterThan(WritingCoachLayoutSupport.accessoryWidth, 0)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.panelSpacing, 0)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.panelInset, 0)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.cornerRadius, 0)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.borderAlpha, 0)
        XCTAssertLessThanOrEqual(WritingCoachLayoutSupport.borderAlpha, 1)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.backgroundAlpha, 0)
        XCTAssertLessThanOrEqual(WritingCoachLayoutSupport.backgroundAlpha, 1)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.headerFontSize, 0)
        XCTAssertGreaterThan(WritingCoachLayoutSupport.itemFontSize, 0)
    }

    func testPrefixesAreNonEmpty() {
        XCTAssertFalse(WritingCoachLayoutSupport.strengthPrefix.isEmpty)
        XCTAssertFalse(WritingCoachLayoutSupport.improvementPrefix.isEmpty)
    }

    func testFallbackStringsAreNonEmpty() {
        XCTAssertFalse(WritingCoachLayoutSupport.emptyStrengthsFallback.isEmpty)
        XCTAssertFalse(WritingCoachLayoutSupport.emptyImprovementsFallback.isEmpty)
    }
}
