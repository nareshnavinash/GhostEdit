import XCTest
@testable import GhostEditCore

final class UpdateCheckSupportTests: XCTestCase {
    // MARK: - parseSemver

    func testParseSemverBasic() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver("4.2.0"), [4, 2, 0])
    }

    func testParseSemverWithPrefix() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver("v4.2.0"), [4, 2, 0])
    }

    func testParseSemverWithBetaSuffix() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver("4.2.0-beta.1"), [4, 2, 0])
    }

    func testParseSemverTwoParts() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver("4.2"), [4, 2])
    }

    func testParseSemverEmpty() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver(""), [])
    }

    func testParseSemverWhitespace() {
        XCTAssertEqual(UpdateCheckSupport.parseSemver("  4.2.0  "), [4, 2, 0])
    }

    // MARK: - isNewer

    func testIsNewerPatchBump() {
        XCTAssertTrue(UpdateCheckSupport.isNewer(current: "4.2.0", latest: "4.2.1"))
    }

    func testIsNewerMinorBump() {
        XCTAssertTrue(UpdateCheckSupport.isNewer(current: "4.2.0", latest: "4.3.0"))
    }

    func testIsNewerMajorBump() {
        XCTAssertTrue(UpdateCheckSupport.isNewer(current: "4.2.0", latest: "5.0.0"))
    }

    func testIsNewerSameVersion() {
        XCTAssertFalse(UpdateCheckSupport.isNewer(current: "4.2.0", latest: "4.2.0"))
    }

    func testIsNewerOlderVersion() {
        XCTAssertFalse(UpdateCheckSupport.isNewer(current: "4.2.1", latest: "4.2.0"))
    }

    func testIsNewerDifferentLengths() {
        XCTAssertTrue(UpdateCheckSupport.isNewer(current: "4.2", latest: "4.2.1"))
        XCTAssertFalse(UpdateCheckSupport.isNewer(current: "4.2.1", latest: "4.2"))
    }

    // MARK: - checkVersion

    func testCheckVersionUpdateAvailable() {
        let info = UpdateCheckSupport.checkVersion(current: "4.2.0", latest: "4.3.0")
        XCTAssertTrue(info.isUpdateAvailable)
        XCTAssertEqual(info.current, "4.2.0")
        XCTAssertEqual(info.latest, "4.3.0")
        XCTAssertNotNil(info.releaseURL)
    }

    func testCheckVersionNoUpdate() {
        let info = UpdateCheckSupport.checkVersion(current: "4.3.0", latest: "4.3.0")
        XCTAssertFalse(info.isUpdateAvailable)
    }

    func testDefaultReleaseURL() {
        XCTAssertTrue(UpdateCheckSupport.defaultReleaseURL.contains("github.com"))
    }
}
