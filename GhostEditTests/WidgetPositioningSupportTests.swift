import XCTest
@testable import GhostEditCore

final class WidgetPositioningSupportTests: XCTestCase {

    // MARK: - widgetOrigin

    func testWidgetPositionBelowField() {
        let origin = WidgetPositioningSupport.widgetOrigin(
            fieldPosition: CGPoint(x: 100, y: 200),
            fieldSize: CGSize(width: 400, height: 30),
            screenHeight: 1080,
            visibleMinY: 0,
            widgetWidth: 36,
            widgetHeight: 36
        )
        // widgetX = 100 + 400 - 36 = 464
        XCTAssertEqual(origin.x, 464)
        // fieldBottomY = 1080 - (200 + 30) = 850
        // widgetY = 850 - 36 - 8 = 806
        XCTAssertEqual(origin.y, 806)
    }

    func testWidgetPositionAboveFieldWhenNoSpaceBelow() {
        let origin = WidgetPositioningSupport.widgetOrigin(
            fieldPosition: CGPoint(x: 100, y: 1040),
            fieldSize: CGSize(width: 400, height: 30),
            screenHeight: 1080,
            visibleMinY: 25,
            widgetWidth: 36,
            widgetHeight: 36
        )
        // fieldBottomY = 1080 - (1040 + 30) = 10
        // widgetY = 10 - 36 - 8 = -34 < visibleMinY 25, so go above
        // finalY = 1080 - 1040 + 8 = 48
        XCTAssertEqual(origin.y, 48)
    }

    func testWidgetPositionClampsXToZero() {
        let origin = WidgetPositioningSupport.widgetOrigin(
            fieldPosition: CGPoint(x: 0, y: 200),
            fieldSize: CGSize(width: 20, height: 30),
            screenHeight: 1080,
            visibleMinY: 0,
            widgetWidth: 36,
            widgetHeight: 36
        )
        // widgetX = 0 + 20 - 36 = -16, clamped to 0
        XCTAssertEqual(origin.x, 0)
    }

    func testWidgetPositionClampsYToZero() {
        let origin = WidgetPositioningSupport.widgetOrigin(
            fieldPosition: CGPoint(x: 100, y: 1070),
            fieldSize: CGSize(width: 400, height: 30),
            screenHeight: 1080,
            visibleMinY: 100,
            widgetWidth: 36,
            widgetHeight: 36
        )
        // fieldBottomY = 1080 - 1100 = -20, widgetY = -20 - 36 - 8 = -64 < 100
        // finalY = 1080 - 1070 + 8 = 18
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }

    // MARK: - widgetFallbackOrigin

    func testFallbackOrigin() {
        let origin = WidgetPositioningSupport.widgetFallbackOrigin(
            screenMaxX: 1920,
            screenMinY: 25,
            widgetWidth: 36
        )
        XCTAssertEqual(origin.x, 1920 - 36 - 20)
        XCTAssertEqual(origin.y, 45)
    }

    // MARK: - popoverOrigin

    func testPopoverOriginAboveWidget() {
        let origin = WidgetPositioningSupport.popoverOrigin(
            widgetFrame: CGRect(x: 500, y: 300, width: 36, height: 36),
            popoverSize: CGSize(width: 280, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        // popoverY = 300 + 36 + 4 = 340 (fits: 340 + 200 = 540 < 1080)
        XCTAssertEqual(origin.x, 500)
        XCTAssertEqual(origin.y, 340)
    }

    func testPopoverOriginBelowWidgetWhenOverflowsTop() {
        let origin = WidgetPositioningSupport.popoverOrigin(
            widgetFrame: CGRect(x: 500, y: 900, width: 36, height: 36),
            popoverSize: CGSize(width: 280, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        // popoverY = 900 + 36 + 4 = 940, 940 + 200 = 1140 > 1080 → below
        // popoverY = 900 - 200 - 4 = 696
        XCTAssertEqual(origin.y, 696)
    }

    func testPopoverOriginClampedRight() {
        let origin = WidgetPositioningSupport.popoverOrigin(
            widgetFrame: CGRect(x: 1800, y: 300, width: 36, height: 36),
            popoverSize: CGSize(width: 280, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        // 1800 + 280 = 2080 > 1920 → clamped to 1920 - 280 = 1640
        XCTAssertEqual(origin.x, 1640)
    }

    func testPopoverOriginClampedLeft() {
        let origin = WidgetPositioningSupport.popoverOrigin(
            widgetFrame: CGRect(x: -100, y: 300, width: 36, height: 36),
            popoverSize: CGSize(width: 280, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        XCTAssertEqual(origin.x, 0)
    }

    // MARK: - shouldReposition

    func testRepositionNormalCase() {
        let result = WidgetPositioningSupport.shouldReposition(
            widgetManuallyDragged: false,
            currentFocusedPID: 100,
            lastDraggedForPID: 100
        )
        XCTAssertEqual(result, .reposition)
    }

    func testRepositionSkipDragged() {
        let result = WidgetPositioningSupport.shouldReposition(
            widgetManuallyDragged: true,
            currentFocusedPID: 100,
            lastDraggedForPID: 100
        )
        XCTAssertEqual(result, .skipDragged)
    }

    func testRepositionResetDragFlag() {
        let result = WidgetPositioningSupport.shouldReposition(
            widgetManuallyDragged: true,
            currentFocusedPID: 200,
            lastDraggedForPID: 100
        )
        XCTAssertEqual(result, .resetDragFlag)
    }

    func testRepositionNilPID() {
        let result = WidgetPositioningSupport.shouldReposition(
            widgetManuallyDragged: true,
            currentFocusedPID: nil,
            lastDraggedForPID: 100
        )
        XCTAssertEqual(result, .skipDragged)
    }

    func testRepositionNilPIDNotDragged() {
        let result = WidgetPositioningSupport.shouldReposition(
            widgetManuallyDragged: false,
            currentFocusedPID: nil,
            lastDraggedForPID: nil
        )
        XCTAssertEqual(result, .reposition)
    }

    // MARK: - adjustIssuesAfterFix

    func testAdjustIssuesRemovesFixedIndex() {
        let issues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"]),
            SpellCheckIssue(word: "wrold", range: NSRange(location: 10, length: 5), kind: .spelling, suggestions: ["world"])
        ]
        let result = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: issues, fixedIndex: 0,
            originalRange: NSRange(location: 0, length: 3), replacementLength: 3
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].word, "wrold")
    }

    func testAdjustIssuesShiftsAfterFix() {
        let issues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"]),
            SpellCheckIssue(word: "wrold", range: NSRange(location: 10, length: 5), kind: .spelling, suggestions: ["world"])
        ]
        // Replace "teh" (3 chars) with "the" (3 chars) — no shift
        let result = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: issues, fixedIndex: 0,
            originalRange: NSRange(location: 0, length: 3), replacementLength: 3
        )
        XCTAssertEqual(result[0].range.location, 10)
    }

    func testAdjustIssuesShiftsWithLengthChange() {
        let issues = [
            SpellCheckIssue(word: "ab", range: NSRange(location: 0, length: 2), kind: .spelling, suggestions: ["abc"]),
            SpellCheckIssue(word: "de", range: NSRange(location: 10, length: 2), kind: .spelling, suggestions: ["def"])
        ]
        // Replace "ab" (2 chars) with "abc" (3 chars) — shift by +1
        let result = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: issues, fixedIndex: 0,
            originalRange: NSRange(location: 0, length: 2), replacementLength: 3
        )
        XCTAssertEqual(result[0].range.location, 11)
    }

    func testAdjustIssuesKeepsBeforeFix() {
        let issues = [
            SpellCheckIssue(word: "first", range: NSRange(location: 0, length: 5), kind: .spelling, suggestions: []),
            SpellCheckIssue(word: "second", range: NSRange(location: 20, length: 6), kind: .spelling, suggestions: ["fixed"])
        ]
        let result = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: issues, fixedIndex: 1,
            originalRange: NSRange(location: 20, length: 6), replacementLength: 5
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].word, "first")
        XCTAssertEqual(result[0].range.location, 0)
    }

    func testAdjustIssuesEmptyList() {
        let result = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: [], fixedIndex: 0,
            originalRange: NSRange(location: 0, length: 3), replacementLength: 3
        )
        XCTAssertTrue(result.isEmpty)
    }
}
