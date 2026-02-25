import XCTest
import CoreGraphics
@testable import GhostEditCore

final class SettingsLayoutSupportTests: XCTestCase {
    func testPreferredWindowHeightUsesMinimumForSmallContent() {
        let height = SettingsLayoutSupport.preferredWindowHeight(for: 120)
        XCTAssertEqual(height, SettingsLayoutSupport.minWindowHeight)
    }

    func testPreferredWindowHeightExpandsForLargerContent() {
        let contentHeight: CGFloat = 600
        let expected = ceil(contentHeight + (SettingsLayoutSupport.verticalInset * 2))
        let height = SettingsLayoutSupport.preferredWindowHeight(for: contentHeight)
        XCTAssertEqual(height, expected)
    }

    func testConstantsAreReasonable() {
        XCTAssertGreaterThan(SettingsLayoutSupport.windowWidth, 0)
        XCTAssertGreaterThan(SettingsLayoutSupport.minWindowHeight, 0)
        XCTAssertGreaterThan(SettingsLayoutSupport.sectionSpacing, 0)
        XCTAssertGreaterThan(SettingsLayoutSupport.rowSpacing, 0)
        XCTAssertGreaterThan(SettingsLayoutSupport.labelWidth, 0)
        XCTAssertGreaterThanOrEqual(SettingsLayoutSupport.groupInset, 0)
        XCTAssertGreaterThanOrEqual(SettingsLayoutSupport.groupCornerRadius, 0)
    }
}
