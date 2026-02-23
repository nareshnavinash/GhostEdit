import XCTest
import CoreGraphics
@testable import GhostEditCore

final class HUDOverlaySupportTests: XCTestCase {

    // MARK: - content(for:)

    func testContentForWorkingState() {
        let content = HUDOverlaySupport.content(for: .working)
        XCTAssertEqual(content.emoji, "\u{1F47B}")
        XCTAssertEqual(content.message, "Working on it...")
    }

    func testContentForSuccessState() {
        let content = HUDOverlaySupport.content(for: .success)
        XCTAssertEqual(content.emoji, "\u{1F47B}")
        XCTAssertEqual(content.message, "Done!")
    }

    func testContentForErrorStateWithDetail() {
        let content = HUDOverlaySupport.content(for: .error("Network timeout"))
        XCTAssertEqual(content.emoji, "\u{1F47B}")
        XCTAssertEqual(content.message, "Network timeout")
    }

    func testContentForErrorStateWithEmptyStringFallsBack() {
        let content = HUDOverlaySupport.content(for: .error(""))
        XCTAssertEqual(content.message, HUDOverlaySupport.defaultErrorMessage)
    }

    func testContentForErrorStateWithWhitespaceFallsBack() {
        let content = HUDOverlaySupport.content(for: .error("   "))
        XCTAssertEqual(content.message, HUDOverlaySupport.defaultErrorMessage)
    }

    func testContentForErrorStateWithNewlinesFallsBack() {
        let content = HUDOverlaySupport.content(for: .error(" \n\t "))
        XCTAssertEqual(content.message, HUDOverlaySupport.defaultErrorMessage)
    }

    // MARK: - showsSpectacles(for:)

    func testShowsSpectaclesForWorkingIsTrue() {
        XCTAssertTrue(HUDOverlaySupport.showsSpectacles(for: .working))
    }

    func testShowsSpectaclesForSuccessIsFalse() {
        XCTAssertFalse(HUDOverlaySupport.showsSpectacles(for: .success))
    }

    func testShowsSpectaclesForErrorIsFalse() {
        XCTAssertFalse(HUDOverlaySupport.showsSpectacles(for: .error("x")))
    }

    // MARK: - autoDismissDelay(for:)

    func testAutoDismissDelayForWorking() {
        XCTAssertEqual(
            HUDOverlaySupport.autoDismissDelay(for: .working),
            HUDOverlaySupport.workingAutoDismissDelay
        )
    }

    func testAutoDismissDelayForSuccess() {
        XCTAssertEqual(
            HUDOverlaySupport.autoDismissDelay(for: .success),
            HUDOverlaySupport.successAutoDismissDelay
        )
    }

    func testAutoDismissDelayForError() {
        XCTAssertEqual(
            HUDOverlaySupport.autoDismissDelay(for: .error("oops")),
            HUDOverlaySupport.errorAutoDismissDelay
        )
    }

    func testWorkingAndSuccessDelaysAreEqual() {
        XCTAssertEqual(
            HUDOverlaySupport.workingAutoDismissDelay,
            HUDOverlaySupport.successAutoDismissDelay
        )
    }

    func testBriefDismissDelayIs1Second() {
        XCTAssertEqual(HUDOverlaySupport.workingAutoDismissDelay, 1.0)
        XCTAssertEqual(HUDOverlaySupport.successAutoDismissDelay, 1.0)
    }

    func testAllStatesReturnNonNilDelay() {
        XCTAssertNotNil(HUDOverlaySupport.autoDismissDelay(for: .working))
        XCTAssertNotNil(HUDOverlaySupport.autoDismissDelay(for: .success))
        XCTAssertNotNil(HUDOverlaySupport.autoDismissDelay(for: .error("x")))
    }

    // MARK: - windowOrigin(screenSize:)

    func testWindowOriginCentersOnScreen() {
        let screenSize = CGSize(width: 1920, height: 1080)
        let origin = HUDOverlaySupport.windowOrigin(screenSize: screenSize)

        let expectedX = (1920 - HUDOverlaySupport.windowWidth) / 2
        let expectedY = (1080 - HUDOverlaySupport.windowHeight) / 2

        XCTAssertEqual(origin.x, expectedX)
        XCTAssertEqual(origin.y, expectedY)
    }

    func testWindowOriginWithSmallScreen() {
        let screenSize = CGSize(width: 400, height: 300)
        let origin = HUDOverlaySupport.windowOrigin(screenSize: screenSize)

        let expectedX = (400 - HUDOverlaySupport.windowWidth) / 2
        let expectedY = (300 - HUDOverlaySupport.windowHeight) / 2

        XCTAssertEqual(origin.x, expectedX)
        XCTAssertEqual(origin.y, expectedY)
    }

    func testWindowOriginWithExactWindowSizeScreen() {
        let screenSize = CGSize(width: HUDOverlaySupport.windowWidth, height: HUDOverlaySupport.windowHeight)
        let origin = HUDOverlaySupport.windowOrigin(screenSize: screenSize)
        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 0)
    }

    // MARK: - Constants sanity checks

    func testLayoutConstantsArePositive() {
        XCTAssertGreaterThan(HUDOverlaySupport.windowWidth, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.windowHeight, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.cornerRadius, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.iconSize, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.messageFontSize, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.verticalSpacing, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.contentInset, 0)
    }

    func testTimingConstantsArePositive() {
        XCTAssertGreaterThan(HUDOverlaySupport.fadeInDuration, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.fadeOutDuration, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.workingAutoDismissDelay, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.successAutoDismissDelay, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.errorAutoDismissDelay, 0)
    }

    func testFadeOutIsLongerThanFadeIn() {
        XCTAssertGreaterThanOrEqual(
            HUDOverlaySupport.fadeOutDuration,
            HUDOverlaySupport.fadeInDuration
        )
    }

    func testDefaultErrorMessageIsNonEmpty() {
        XCTAssertFalse(HUDOverlaySupport.defaultErrorMessage.isEmpty)
    }

    // MARK: - Ghost SVG data sanity checks

    func testGhostPathsAreNonEmpty() {
        XCTAssertFalse(HUDOverlaySupport.ghostBodyPath.isEmpty)
        XCTAssertFalse(HUDOverlaySupport.ghostMouthPath.isEmpty)
        XCTAssertFalse(HUDOverlaySupport.ghostBridgePath.isEmpty)
        XCTAssertFalse(HUDOverlaySupport.ghostLeftArmPath.isEmpty)
        XCTAssertFalse(HUDOverlaySupport.ghostRightArmPath.isEmpty)
    }

    func testGhostViewBoxValuesArePositive() {
        XCTAssertGreaterThan(HUDOverlaySupport.ghostViewBoxSize, 0)
        XCTAssertGreaterThan(HUDOverlaySupport.ghostStrokeWidth, 0)
    }

    func testGhostEyePropertiesArePositive() {
        let leftEye = HUDOverlaySupport.ghostLeftEye
        XCTAssertGreaterThan(leftEye.rx, 0)
        XCTAssertGreaterThan(leftEye.ry, 0)
        XCTAssertGreaterThan(leftEye.highlightR, 0)
        XCTAssertGreaterThan(leftEye.lensR, 0)

        let rightEye = HUDOverlaySupport.ghostRightEye
        XCTAssertGreaterThan(rightEye.rx, 0)
        XCTAssertGreaterThan(rightEye.ry, 0)
        XCTAssertGreaterThan(rightEye.highlightR, 0)
        XCTAssertGreaterThan(rightEye.lensR, 0)
    }

    func testGhostEyesAreSymmetric() {
        let left = HUDOverlaySupport.ghostLeftEye
        let right = HUDOverlaySupport.ghostRightEye
        XCTAssertEqual(left.rx, right.rx)
        XCTAssertEqual(left.ry, right.ry)
        XCTAssertEqual(left.highlightR, right.highlightR)
        XCTAssertEqual(left.lensR, right.lensR)
        XCTAssertEqual(left.rotation, -right.rotation)
    }

    func testGhostBodyPathStartsWithMove() {
        XCTAssertTrue(HUDOverlaySupport.ghostBodyPath.hasPrefix("M"))
    }

    func testGhostBodyPathEndsWithClose() {
        XCTAssertTrue(HUDOverlaySupport.ghostBodyPath.hasSuffix("Z"))
    }

    // MARK: - Equatable conformance

    func testHUDOverlayStateEquatable() {
        XCTAssertEqual(HUDOverlayState.working, HUDOverlayState.working)
        XCTAssertEqual(HUDOverlayState.success, HUDOverlayState.success)
        XCTAssertEqual(HUDOverlayState.error("a"), HUDOverlayState.error("a"))
        XCTAssertNotEqual(HUDOverlayState.working, HUDOverlayState.success)
        XCTAssertNotEqual(HUDOverlayState.error("a"), HUDOverlayState.error("b"))
        XCTAssertNotEqual(HUDOverlayState.working, HUDOverlayState.error("a"))
        XCTAssertNotEqual(HUDOverlayState.success, HUDOverlayState.error("a"))
    }

    func testHUDOverlayContentEquatable() {
        let a = HUDOverlayContent(emoji: "X", message: "hello")
        let b = HUDOverlayContent(emoji: "X", message: "hello")
        let c = HUDOverlayContent(emoji: "Y", message: "hello")
        let d = HUDOverlayContent(emoji: "X", message: "world")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    // MARK: - Content consistency

    func testAllStatesProduceNonEmptyContent() {
        for state: HUDOverlayState in [.working, .success, .error("test")] {
            let content = HUDOverlaySupport.content(for: state)
            XCTAssertFalse(content.emoji.isEmpty, "emoji should not be empty for \(state)")
            XCTAssertFalse(content.message.isEmpty, "message should not be empty for \(state)")
        }
    }

    func testWorkingAndSuccessHaveDifferentMessages() {
        let working = HUDOverlaySupport.content(for: .working)
        let success = HUDOverlaySupport.content(for: .success)
        XCTAssertNotEqual(working.message, success.message)
    }

    func testGhostEyeEquatable() {
        let eye1 = HUDOverlaySupport.ghostLeftEye
        let eye2 = HUDOverlaySupport.GhostEye(
            cx: 420, cy: 390, rx: 48, ry: 60, rotation: -8,
            highlightCX: 436, highlightCY: 370, highlightR: 13,
            lensR: 78
        )
        let eye3 = HUDOverlaySupport.ghostRightEye
        XCTAssertEqual(eye1, eye2)
        XCTAssertNotEqual(eye1, eye3)
    }
}
