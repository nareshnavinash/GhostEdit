import XCTest
@testable import GhostEditCore

final class HUDContentSupportTests: XCTestCase {

    // MARK: - isDiffState

    func testIsDiffStateWorking() {
        XCTAssertFalse(HUDContentSupport.isDiffState(.working))
    }

    func testIsDiffStateSuccess() {
        XCTAssertFalse(HUDContentSupport.isDiffState(.success))
    }

    func testIsDiffStateSuccessWithCount() {
        XCTAssertFalse(HUDContentSupport.isDiffState(.successWithCount(10)))
    }

    func testIsDiffStateSuccessWithDiff() {
        let segments = [DiffSegment(kind: .equal, text: "hello")]
        XCTAssertTrue(HUDContentSupport.isDiffState(.successWithDiff(segments, toolsUsed: "test")))
    }

    func testIsDiffStateError() {
        XCTAssertFalse(HUDContentSupport.isDiffState(.error("oops")))
    }

    func testIsDiffStateFallback() {
        XCTAssertFalse(HUDContentSupport.isDiffState(.fallback))
    }

    // MARK: - showsSpinner

    func testShowsSpinnerWorking() {
        XCTAssertTrue(HUDContentSupport.showsSpinner(for: .working))
    }

    func testShowsSpinnerSuccess() {
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .success))
    }

    func testShowsSpinnerSuccessWithCount() {
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .successWithCount(5)))
    }

    func testShowsSpinnerError() {
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .error("err")))
    }

    func testShowsSpinnerFallback() {
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .fallback))
    }

    func testShowsSpinnerDiff() {
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .successWithDiff([], toolsUsed: "")))
    }

    // MARK: - tintColorName

    func testTintColorWorking() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .working), "systemBlue")
    }

    func testTintColorSuccess() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .success), "systemGreen")
    }

    func testTintColorSuccessWithCount() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .successWithCount(10)), "systemGreen")
    }

    func testTintColorSuccessWithDiff() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .successWithDiff([], toolsUsed: "")), "systemGreen")
    }

    func testTintColorFallback() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .fallback), "systemOrange")
    }

    func testTintColorError() {
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .error("err")), "systemRed")
    }

    // MARK: - effectiveDismissDelay

    func testEffectiveDismissDelayWithOverride() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: 99.0, state: .working)
        XCTAssertEqual(delay, 99.0)
    }

    func testEffectiveDismissDelayNoOverrideWorking() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .working)
        XCTAssertEqual(delay, HUDOverlaySupport.workingAutoDismissDelay)
    }

    func testEffectiveDismissDelayNoOverrideSuccess() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .success)
        XCTAssertEqual(delay, HUDOverlaySupport.successAutoDismissDelay)
    }

    func testEffectiveDismissDelayNoOverrideError() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .error("err"))
        XCTAssertEqual(delay, HUDOverlaySupport.errorAutoDismissDelay)
    }

    func testEffectiveDismissDelayNoOverrideDiff() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .successWithDiff([], toolsUsed: ""))
        XCTAssertEqual(delay, HUDOverlaySupport.diffAutoDismissDelay)
    }

    func testEffectiveDismissDelayNoOverrideFallback() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .fallback)
        XCTAssertEqual(delay, HUDOverlaySupport.successAutoDismissDelay)
    }

    func testEffectiveDismissDelayNoOverrideSuccessWithCount() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: nil, state: .successWithCount(5))
        XCTAssertEqual(delay, HUDOverlaySupport.successAutoDismissDelay)
    }

    // MARK: - filterSegmentsForHUD

    func testFilterSegmentsRemovesDeletions() {
        let segments = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "bad"),
            DiffSegment(kind: .insertion, text: "good")
        ]
        let filtered = HUDContentSupport.filterSegmentsForHUD(segments)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.kind != .deletion })
    }

    func testFilterSegmentsEmpty() {
        let filtered = HUDContentSupport.filterSegmentsForHUD([])
        XCTAssertTrue(filtered.isEmpty)
    }

    func testFilterSegmentsAllEqual() {
        let segments = [DiffSegment(kind: .equal, text: "Hello")]
        let filtered = HUDContentSupport.filterSegmentsForHUD(segments)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterSegmentsAllDeletions() {
        let segments = [
            DiffSegment(kind: .deletion, text: "removed1"),
            DiffSegment(kind: .deletion, text: "removed2")
        ]
        let filtered = HUDContentSupport.filterSegmentsForHUD(segments)
        XCTAssertTrue(filtered.isEmpty)
    }
}
