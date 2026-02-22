import XCTest
@testable import GhostEditCore

final class AccessibilitySupportTests: XCTestCase {
    func testGuidanceTextContainsSystemPathAndCommands() {
        let text = AccessibilitySupport.guidanceText(appName: "GhostEdit")
        XCTAssertTrue(text.contains("System Settings > Privacy & Security > Accessibility"))
        XCTAssertTrue(text.contains("Cmd+C"))
        XCTAssertTrue(text.contains("Cmd+V"))
    }

    func testGuidanceTextIncludesUpdateSigningTip() {
        let text = AccessibilitySupport.guidanceText(appName: "GhostEdit")
        XCTAssertTrue(text.contains("after an app update"))
        XCTAssertTrue(text.contains("signed with a consistent identity"))
        XCTAssertTrue(text.contains("persist across updates"))
    }
}
