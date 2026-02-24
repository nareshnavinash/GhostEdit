import XCTest
@testable import GhostEditCore

final class TooltipSupportTests: XCTestCase {
    func testDefaultTooltipWhenNoData() {
        let result = TooltipSupport.tooltip(
            lastOriginal: nil,
            lastCorrected: nil,
            lastTime: nil,
            provider: nil,
            model: nil
        )
        XCTAssertEqual(result, "GhostEdit")
    }

    func testDefaultTooltipWhenOriginalIsEmpty() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "",
            lastCorrected: "corrected",
            lastTime: nil,
            provider: nil,
            model: nil
        )
        XCTAssertEqual(result, "GhostEdit")
    }

    func testTooltipWithCorrectedText() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "hello",
            lastCorrected: "Hello.",
            lastTime: nil,
            provider: nil,
            model: nil
        )
        XCTAssertTrue(result.contains("GhostEdit"))
        XCTAssertTrue(result.contains("Hello."))
    }

    func testTooltipWithTimeAndProvider() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = Date(timeIntervalSince1970: 1_700_000_000)

        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: time,
            provider: "Claude",
            model: "haiku",
            timeFormatter: formatter
        )
        XCTAssertTrue(result.contains("GhostEdit"))
        XCTAssertTrue(result.contains("Last:"))
        XCTAssertTrue(result.contains("Test."))
        XCTAssertTrue(result.contains("via Claude (haiku)"))
    }

    func testTooltipWithProviderNoModel() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: nil,
            provider: "Gemini",
            model: nil
        )
        XCTAssertTrue(result.contains("via Gemini"))
        XCTAssertFalse(result.contains("()"))
    }

    func testTooltipWithEmptyModel() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: nil,
            provider: "Claude",
            model: ""
        )
        XCTAssertTrue(result.contains("via Claude"))
        XCTAssertFalse(result.contains("()"))
    }

    func testTooltipWithTimeAndNoCustomFormatter() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: time,
            provider: nil,
            model: nil
        )
        XCTAssertTrue(result.contains("GhostEdit"))
        XCTAssertTrue(result.contains("Last:"))
    }

    func testTooltipWithNilProvider() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: nil,
            provider: nil,
            model: nil
        )
        XCTAssertTrue(result.contains("GhostEdit"))
        XCTAssertTrue(result.contains("Test."))
        XCTAssertFalse(result.contains("via"))
    }

    func testTooltipWithEmptyProvider() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: "Test.",
            lastTime: nil,
            provider: "",
            model: "haiku"
        )
        XCTAssertFalse(result.contains("via"))
    }

    func testTooltipWithNilCorrected() {
        let result = TooltipSupport.tooltip(
            lastOriginal: "test",
            lastCorrected: nil,
            lastTime: nil,
            provider: nil,
            model: nil
        )
        XCTAssertEqual(result, "GhostEdit")
    }

    // MARK: - truncatePreview

    func testTruncatePreviewShortText() {
        let result = TooltipSupport.truncatePreview("hello", maxLength: 20)
        XCTAssertEqual(result, "hello")
    }

    func testTruncatePreviewLongText() {
        let longText = String(repeating: "a", count: 100)
        let result = TooltipSupport.truncatePreview(longText, maxLength: 20)
        XCTAssertEqual(result.count, 20)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testTruncatePreviewNewlinesCollapsed() {
        let result = TooltipSupport.truncatePreview("hello\nworld", maxLength: 60)
        XCTAssertEqual(result, "hello world")
    }

    func testTruncatePreviewTrimsWhitespace() {
        let result = TooltipSupport.truncatePreview("  hello  ", maxLength: 60)
        XCTAssertEqual(result, "hello")
    }
}
