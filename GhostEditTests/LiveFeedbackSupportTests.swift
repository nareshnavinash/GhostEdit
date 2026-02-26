import XCTest
import CoreGraphics
@testable import GhostEditCore

final class LiveFeedbackSupportTests: XCTestCase {

    // MARK: - Widget Layout Constants

    func testWidgetLayoutConstantsArePositive() {
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetWidth, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetHeight, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetCornerRadius, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetFontSize, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetPadding, 0)
        XCTAssertGreaterThanOrEqual(LiveFeedbackSupport.widgetOffsetY, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetIconSize, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetDotSize, 0)
    }

    func testWidgetIsCircular() {
        // Corner radius should be half the width for a circular widget
        XCTAssertEqual(LiveFeedbackSupport.widgetCornerRadius, LiveFeedbackSupport.widgetWidth / 2)
    }

    func testWidgetIsSquare() {
        XCTAssertEqual(LiveFeedbackSupport.widgetWidth, LiveFeedbackSupport.widgetHeight)
    }

    // MARK: - Popover Layout Constants

    func testPopoverLayoutConstantsArePositive() {
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverWidth, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverRowHeight, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverMaxVisibleRows, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverCornerRadius, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverPadding, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverRowIconSize, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverRowIconPadding, 0)
        XCTAssertGreaterThanOrEqual(LiveFeedbackSupport.popoverRowArrowPadding, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverRowVerticalPadding, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.popoverRowHoverAlpha, 0)
        XCTAssertLessThanOrEqual(LiveFeedbackSupport.popoverRowHoverAlpha, 1.0)
    }

    // MARK: - Issue Action Button Constants

    func testIssueActionButtonConstantsArePositive() {
        XCTAssertGreaterThan(LiveFeedbackSupport.issueActionButtonSize, 0)
        XCTAssertGreaterThanOrEqual(LiveFeedbackSupport.issueActionButtonSpacing, 0)
    }

    func testIssueActionButtonSizeFitsInRow() {
        XCTAssertLessThanOrEqual(
            LiveFeedbackSupport.issueActionButtonSize,
            LiveFeedbackSupport.popoverRowHeight
        )
    }

    // MARK: - Timing Constants

    func testTimingConstantsArePositive() {
        XCTAssertGreaterThan(LiveFeedbackSupport.pollingInterval, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetFadeInDuration, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.widgetFadeOutDuration, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.cleanAutoDismissDelay, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.issuePopoverAutoDismissDelay, 0)
        XCTAssertGreaterThan(LiveFeedbackSupport.hoverDismissRestartDelay, 0)
    }

    func testHoverDismissRestartDelayIsLessThanIssuePopoverDelay() {
        XCTAssertLessThan(
            LiveFeedbackSupport.hoverDismissRestartDelay,
            LiveFeedbackSupport.issuePopoverAutoDismissDelay
        )
    }

    func testIssuePopoverDelayIsAtLeastFiveSeconds() {
        XCTAssertGreaterThanOrEqual(LiveFeedbackSupport.issuePopoverAutoDismissDelay, 5.0)
    }

    // MARK: - statusText

    func testStatusTextIdle() {
        XCTAssertEqual(LiveFeedbackSupport.statusText(for: .idle), "Live Check")
    }

    func testStatusTextChecking() {
        let text = LiveFeedbackSupport.statusText(for: .checking)
        XCTAssertTrue(text.contains("Checking"))
    }

    func testStatusTextClean() {
        XCTAssertEqual(LiveFeedbackSupport.statusText(for: .clean), "All clear")
    }

    func testStatusTextSingleIssue() {
        XCTAssertEqual(LiveFeedbackSupport.statusText(for: .issues(1)), "1 issue found")
    }

    func testStatusTextMultipleIssues() {
        XCTAssertEqual(LiveFeedbackSupport.statusText(for: .issues(5)), "5 issues found")
    }

    func testStatusTextZeroIssues() {
        XCTAssertEqual(LiveFeedbackSupport.statusText(for: .issues(0)), "0 issues found")
    }

    func testStatusTextUnavailableWithReason() {
        XCTAssertEqual(
            LiveFeedbackSupport.statusText(for: .unavailable("No text field")),
            "No text field"
        )
    }

    func testStatusTextUnavailableEmptyReason() {
        XCTAssertEqual(
            LiveFeedbackSupport.statusText(for: .unavailable("")),
            "Unavailable"
        )
    }

    func testStatusTextUnavailableWhitespaceReason() {
        XCTAssertEqual(
            LiveFeedbackSupport.statusText(for: .unavailable("  \n ")),
            "Unavailable"
        )
    }

    // MARK: - statusColorName

    func testStatusColorNameIdle() {
        XCTAssertEqual(LiveFeedbackSupport.statusColorName(for: .idle), "systemGray")
    }

    func testStatusColorNameChecking() {
        XCTAssertEqual(LiveFeedbackSupport.statusColorName(for: .checking), "systemOrange")
    }

    func testStatusColorNameClean() {
        XCTAssertEqual(LiveFeedbackSupport.statusColorName(for: .clean), "systemGreen")
    }

    func testStatusColorNameIssues() {
        XCTAssertEqual(LiveFeedbackSupport.statusColorName(for: .issues(3)), "systemRed")
    }

    func testStatusColorNameUnavailable() {
        XCTAssertEqual(LiveFeedbackSupport.statusColorName(for: .unavailable("x")), "systemGray")
    }

    // MARK: - autoDismissDelay

    func testAutoDismissDelayClean() {
        XCTAssertEqual(
            LiveFeedbackSupport.autoDismissDelay(for: .clean),
            LiveFeedbackSupport.cleanAutoDismissDelay
        )
    }

    func testAutoDismissDelayIdleIsNil() {
        XCTAssertNil(LiveFeedbackSupport.autoDismissDelay(for: .idle))
    }

    func testAutoDismissDelayCheckingIsNil() {
        XCTAssertNil(LiveFeedbackSupport.autoDismissDelay(for: .checking))
    }

    func testAutoDismissDelayIssuesIsNil() {
        XCTAssertNil(LiveFeedbackSupport.autoDismissDelay(for: .issues(5)))
    }

    func testAutoDismissDelayUnavailableIsNil() {
        XCTAssertNil(LiveFeedbackSupport.autoDismissDelay(for: .unavailable("x")))
    }

    // MARK: - popoverHeight

    func testPopoverHeightSingleIssue() {
        let height = LiveFeedbackSupport.popoverHeight(for: 1)
        let expected = LiveFeedbackSupport.popoverRowHeight + LiveFeedbackSupport.popoverPadding * 2
        XCTAssertEqual(height, expected)
    }

    func testPopoverHeightMultipleIssues() {
        let height = LiveFeedbackSupport.popoverHeight(for: 3)
        let expected = 3 * LiveFeedbackSupport.popoverRowHeight + LiveFeedbackSupport.popoverPadding * 2
        XCTAssertEqual(height, expected)
    }

    func testPopoverHeightCapsAtMaxVisibleRows() {
        let many = LiveFeedbackSupport.popoverMaxVisibleRows + 10
        let height = LiveFeedbackSupport.popoverHeight(for: many)
        let maxHeight = CGFloat(LiveFeedbackSupport.popoverMaxVisibleRows) * LiveFeedbackSupport.popoverRowHeight + LiveFeedbackSupport.popoverPadding * 2
        XCTAssertEqual(height, maxHeight)
    }

    func testPopoverHeightZeroIssuesReturnsMinimum() {
        let height = LiveFeedbackSupport.popoverHeight(for: 0)
        let minHeight = LiveFeedbackSupport.popoverRowHeight + LiveFeedbackSupport.popoverPadding * 2
        XCTAssertEqual(height, minHeight)
    }

    func testPopoverHeightExactlyAtMaxRows() {
        let count = LiveFeedbackSupport.popoverMaxVisibleRows
        let height = LiveFeedbackSupport.popoverHeight(for: count)
        let expected = CGFloat(count) * LiveFeedbackSupport.popoverRowHeight + LiveFeedbackSupport.popoverPadding * 2
        XCTAssertEqual(height, expected)
    }

    // MARK: - LiveFeedbackState Equatable

    func testStateEquatable() {
        XCTAssertEqual(LiveFeedbackState.idle, LiveFeedbackState.idle)
        XCTAssertEqual(LiveFeedbackState.checking, LiveFeedbackState.checking)
        XCTAssertEqual(LiveFeedbackState.clean, LiveFeedbackState.clean)
        XCTAssertEqual(LiveFeedbackState.issues(3), LiveFeedbackState.issues(3))
        XCTAssertEqual(LiveFeedbackState.unavailable("x"), LiveFeedbackState.unavailable("x"))
    }

    func testStateNotEqual() {
        XCTAssertNotEqual(LiveFeedbackState.idle, LiveFeedbackState.checking)
        XCTAssertNotEqual(LiveFeedbackState.idle, LiveFeedbackState.clean)
        XCTAssertNotEqual(LiveFeedbackState.checking, LiveFeedbackState.clean)
        XCTAssertNotEqual(LiveFeedbackState.issues(1), LiveFeedbackState.issues(2))
        XCTAssertNotEqual(LiveFeedbackState.unavailable("a"), LiveFeedbackState.unavailable("b"))
        XCTAssertNotEqual(LiveFeedbackState.clean, LiveFeedbackState.issues(0))
        XCTAssertNotEqual(LiveFeedbackState.idle, LiveFeedbackState.unavailable("x"))
    }

    // MARK: - All states produce non-empty content

    func testAllStatesProduceNonEmptyStatusText() {
        let states: [LiveFeedbackState] = [
            .idle, .checking, .clean, .issues(1), .issues(5), .unavailable("test")
        ]
        for state in states {
            let text = LiveFeedbackSupport.statusText(for: state)
            XCTAssertFalse(text.isEmpty, "statusText should not be empty for \(state)")
        }
    }

    func testAllStatesProduceNonEmptyColorName() {
        let states: [LiveFeedbackState] = [
            .idle, .checking, .clean, .issues(1), .unavailable("test")
        ]
        for state in states {
            let color = LiveFeedbackSupport.statusColorName(for: state)
            XCTAssertFalse(color.isEmpty, "statusColorName should not be empty for \(state)")
        }
    }
}
