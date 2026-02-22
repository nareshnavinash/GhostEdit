import XCTest
@testable import GhostEditCore

final class WritingCoachSupportTests: XCTestCase {
    func testBuildInputIncludesNumberedSamplesAndSkipsEmptyValues() {
        let input = WritingCoachSupport.buildInput(from: [
            "First sample.",
            "   ",
            "\nSecond sample\n"
        ])

        XCTAssertTrue(input.contains("Analyze these writing samples from one author:"))
        XCTAssertTrue(input.contains("Sample 1:\nFirst sample."))
        XCTAssertTrue(input.contains("Sample 2:\nSecond sample"))
        XCTAssertFalse(input.contains("Sample 3"))
    }

    func testBuildInputHandlesNoSamples() {
        let input = WritingCoachSupport.buildInput(from: [" ", "\n"])
        XCTAssertEqual(input, "No writing samples were provided.")
    }

    func testParseInsightsParsesStrictJSONPayload() {
        let response = """
        {"positives":["Clear structure","Professional tone"],"improvements":["Shorten long sentences","Use stronger verbs"]}
        """

        let parsed = WritingCoachSupport.parseInsights(from: response)
        XCTAssertEqual(
            parsed,
            WritingCoachInsights(
                positives: ["Clear structure", "Professional tone"],
                improvements: ["Shorten long sentences", "Use stronger verbs"]
            )
        )
    }

    func testParseInsightsFallsBackToBulletedSections() {
        let response = """
        Positives
        - Clear intent
        - Friendly voice

        Improvements
        1. Tighten openings
        2) Reduce filler
        """

        let parsed = WritingCoachSupport.parseInsights(from: response)
        XCTAssertEqual(
            parsed,
            WritingCoachInsights(
                positives: ["Clear intent", "Friendly voice"],
                improvements: ["Tighten openings", "Reduce filler"]
            )
        )
    }

    func testParseInsightsTreatsUnsectionedBulletsAsImprovements() {
        let response = """
        - Use shorter transitions
        - Prefer active voice
        """

        let parsed = WritingCoachSupport.parseInsights(from: response)
        XCTAssertEqual(
            parsed,
            WritingCoachInsights(
                positives: [],
                improvements: ["Use shorter transitions", "Prefer active voice"]
            )
        )
    }

    func testParseInsightsReturnsNilWhenNothingUsefulExists() {
        XCTAssertNil(WritingCoachSupport.parseInsights(from: ""))
        XCTAssertNil(WritingCoachSupport.parseInsights(from: "Random paragraph without bullet structure"))
        XCTAssertNil(WritingCoachSupport.parseInsights(from: "{\"positives\":[],\"improvements\":[]}"))
    }

    func testParseInsightsIgnoresInvalidNumberedMarkers() {
        let response = """
        Improvements
        1- Invalid marker
        2. Valid marker
        """

        let parsed = WritingCoachSupport.parseInsights(from: response)
        XCTAssertEqual(
            parsed,
            WritingCoachInsights(
                positives: [],
                improvements: ["Valid marker"]
            )
        )
    }

    func testPopupTextRendersNumberedListsAndFallbacks() {
        let popup = WritingCoachSupport.popupText(
            for: WritingCoachInsights(
                positives: ["Clear narrative"],
                improvements: []
            ),
            sampleCount: 3
        )

        XCTAssertTrue(popup.contains("Reviewed 3 writing sample(s)."))
        XCTAssertTrue(popup.contains("Positives"))
        XCTAssertTrue(popup.contains("1. Clear narrative"))
        XCTAssertTrue(popup.contains("Improvements"))
        XCTAssertTrue(popup.contains("1. No specific improvements suggested yet."))
    }
}
