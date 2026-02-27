import XCTest
@testable import GhostEditCore

final class StatusDisplaySupportTests: XCTestCase {

    // MARK: - Green states

    func testIdle() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Idle"), .green)
    }

    func testLastCorrection() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Last correction at 3:45 PM"), .green)
    }

    func testSettingsSaved() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Settings saved"), .green)
    }

    func testUnknownTextIsGreen() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Something else entirely"), .green)
    }

    func testEmptyTextIsGreen() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: ""), .green)
    }

    // MARK: - Orange states

    func testProcessing() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Processing text..."), .orange)
    }

    func testWorking() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Working on correction"), .orange)
    }

    func testCopying() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Copying selection"), .orange)
    }

    func testAnalyzing() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Analyzing text"), .orange)
    }

    func testChecking() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Checking spelling"), .orange)
    }

    func testRetrying() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Retrying request"), .orange)
    }

    // MARK: - Red states

    func testFailed() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Correction failed"), .red)
    }

    func testNotFound() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "CLI not found"), .red)
    }

    func testRequired() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Accessibility permission required"), .red)
    }

    func testNoText() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "No text selected"), .red)
    }

    func testPermission() {
        XCTAssertEqual(StatusDisplaySupport.statusColor(for: "Need permission to access"), .red)
    }
}
