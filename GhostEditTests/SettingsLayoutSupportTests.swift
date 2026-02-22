import XCTest
import CoreGraphics
@testable import GhostEditCore

final class SettingsLayoutSupportTests: XCTestCase {
    func testPreferredWindowHeightUsesMinimumForSmallContent() {
        let height = SettingsLayoutSupport.preferredWindowHeight(for: 120)
        XCTAssertEqual(height, SettingsLayoutSupport.minWindowHeight)
    }

    func testPreferredWindowHeightExpandsForLargerContent() {
        let contentHeight: CGFloat = 500
        let expected = ceil(contentHeight + (SettingsLayoutSupport.verticalInset * 2))
        let height = SettingsLayoutSupport.preferredWindowHeight(for: contentHeight)
        XCTAssertEqual(height, expected)
    }
}
