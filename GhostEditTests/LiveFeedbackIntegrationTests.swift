import XCTest
@testable import GhostEditCore

final class LiveFeedbackIntegrationTests: XCTestCase {

    // MARK: - State machine full cycle

    func testStateMachineFullCycle() {
        // Start idle
        var state: LiveFeedbackState = .idle

        // User types text
        let (s1, e1) = LiveFeedbackStateMachine.transition(state: state, event: .textChanged("Hello wrold"))
        state = s1
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(e1, [.runSpellCheck("Hello wrold")])

        // Spell check finds issues
        let issues = [
            SpellCheckIssue(word: "wrold", range: NSRange(location: 6, length: 5), kind: .spelling, suggestions: ["world"])
        ]
        let (s2, e2) = LiveFeedbackStateMachine.transition(state: state, event: .spellCheckComplete(issues))
        state = s2
        XCTAssertEqual(state, .issues(1))
        XCTAssertEqual(e2.count, 1)

        // User fixes the text
        let (s3, e3) = LiveFeedbackStateMachine.transition(state: state, event: .textChanged("Hello world"))
        state = s3
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(e3, [.runSpellCheck("Hello world")])

        // Spell check finds no issues
        let (s4, e4) = LiveFeedbackStateMachine.transition(state: state, event: .spellCheckComplete([]))
        state = s4
        XCTAssertEqual(state, .clean)
        XCTAssertEqual(e4, [.clearUI])

        // Focus lost
        let (s5, _) = LiveFeedbackStateMachine.transition(state: state, event: .focusLost)
        XCTAssertEqual(s5, .idle)
    }

    func testStaleModelResultsDiscarded() {
        XCTAssertTrue(LiveFeedbackStateMachine.isResultStale(resultGeneration: 3, currentGeneration: 5))
        XCTAssertFalse(LiveFeedbackStateMachine.isResultStale(resultGeneration: 5, currentGeneration: 5))
    }

    func testCombinedIssuesWithIgnoredWords() {
        let spellIssues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"]),
            SpellCheckIssue(word: "programing", range: NSRange(location: 10, length: 10), kind: .spelling, suggestions: ["programming"])
        ]
        let modelIssues = [
            SpellCheckIssue(word: "wrold", range: NSRange(location: 25, length: 5), kind: .grammar, suggestions: ["world"])
        ]
        let combined = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spellIssues,
            modelIssues: modelIssues,
            ignoredWords: ["teh"]
        )
        // "teh" filtered out, "programing" and "wrold" remain
        XCTAssertEqual(combined.count, 2)
        XCTAssertFalse(combined.contains { $0.word == "teh" })
    }

    func testOverlappingIssuesDeduplication() {
        let spellIssues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"])
        ]
        let modelIssues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .grammar, suggestions: ["the"])
        ]
        let combined = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spellIssues,
            modelIssues: modelIssues,
            ignoredWords: []
        )
        XCTAssertEqual(combined.count, 1)
    }

    // MARK: - Widget positioning integration

    func testWidgetFollowsTextFieldBelow() {
        let origin = WidgetPositioningSupport.widgetOrigin(
            fieldPosition: CGPoint(x: 100, y: 200),
            fieldSize: CGSize(width: 400, height: 30),
            screenHeight: 1080,
            visibleMinY: 25,
            widgetWidth: 36,
            widgetHeight: 36
        )
        // Widget should be below field
        let fieldBottomInCocoa = 1080.0 - (200.0 + 30.0) // = 850
        XCTAssertLessThan(origin.y, fieldBottomInCocoa)
    }

    func testWidgetPositionsThenPopoverAbove() {
        let widgetFrame = CGRect(x: 500, y: 900, width: 36, height: 36)
        let popoverOrigin = WidgetPositioningSupport.popoverOrigin(
            widgetFrame: widgetFrame,
            popoverSize: CGSize(width: 280, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        // Popover should try above widget since y + height = 940 + 200 = 1140 > 1080
        XCTAssertLessThan(popoverOrigin.y, widgetFrame.origin.y)
    }

    // MARK: - Issue adjustment after fix

    func testFixingFirstIssueShiftsSubsequent() {
        let issues = [
            SpellCheckIssue(word: "ab", range: NSRange(location: 0, length: 2), kind: .spelling, suggestions: ["abc"]),
            SpellCheckIssue(word: "de", range: NSRange(location: 5, length: 2), kind: .spelling, suggestions: ["def"]),
            SpellCheckIssue(word: "gh", range: NSRange(location: 10, length: 2), kind: .spelling, suggestions: ["ghi"])
        ]
        // Fix "ab" (2 chars) → "abc" (3 chars): delta = +1
        let adjusted = WidgetPositioningSupport.adjustIssuesAfterFix(
            issues: issues, fixedIndex: 0,
            originalRange: NSRange(location: 0, length: 2), replacementLength: 3
        )
        XCTAssertEqual(adjusted.count, 2) // Fixed issue removed
        XCTAssertEqual(adjusted[0].range.location, 6) // 5 + 1
        XCTAssertEqual(adjusted[1].range.location, 11) // 10 + 1
    }

    // MARK: - History filter integration

    func testHistoryFilterAndTimestamp() {
        let now = Date()

        // Test relative timestamp
        let justNow = HistoryFilterSupport.relativeTimestamp(
            for: now.addingTimeInterval(-30), now: now,
            timeOnlyFormatter: { _ in "10:30 AM" },
            fullFormatter: { _ in "Jan 15" }
        )
        XCTAssertEqual(justNow, "Just now")

        let hoursAgo = HistoryFilterSupport.relativeTimestamp(
            for: now.addingTimeInterval(-7200), now: now,
            timeOnlyFormatter: { _ in "10:30 AM" },
            fullFormatter: { _ in "Jan 15" }
        )
        XCTAssertEqual(hoursAgo, "2 hours ago")
    }

    func testDurationColorCoding() {
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 500), "systemGreen")
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 3000), "systemOrange")
        XCTAssertEqual(HistoryFilterSupport.durationColorName(milliseconds: 7000), "systemRed")
    }

    // MARK: - HUD state integration

    func testHUDStateTransitions() {
        // Working state
        XCTAssertTrue(HUDContentSupport.showsSpinner(for: .working))
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .working), "systemBlue")
        XCTAssertFalse(HUDContentSupport.isDiffState(.working))

        // Success state
        XCTAssertFalse(HUDContentSupport.showsSpinner(for: .success))
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .success), "systemGreen")

        // Error state
        XCTAssertEqual(HUDContentSupport.tintColorName(for: .error("oops")), "systemRed")

        // Diff state
        let segments = [DiffSegment(kind: .equal, text: "test")]
        XCTAssertTrue(HUDContentSupport.isDiffState(.successWithDiff(segments, toolsUsed: "test")))
    }

    func testHUDDismissDelayWithOverride() {
        let delay = HUDContentSupport.effectiveDismissDelay(override: 10.0, state: .working)
        XCTAssertEqual(delay, 10.0)
    }

    // MARK: - Streaming preview integration

    func testStreamingPreviewSimilarityAndNavigation() {
        let similarity = StreamingPreviewLogic.computeSimilarity(
            old: "Hello world", new: "Hello world"
        )
        XCTAssertEqual(similarity, 100)

        let segments = [
            DiffSegment(kind: .equal, text: "Hello "),
            DiffSegment(kind: .deletion, text: "wrold"),
            DiffSegment(kind: .insertion, text: "world")
        ]
        let ranges = StreamingPreviewLogic.buildChangeRanges(from: segments)
        XCTAssertEqual(ranges.count, 1) // Merged deletion+insertion

        let (prev, next) = StreamingPreviewLogic.navButtonStates(changeCount: 1, currentIndex: 0)
        XCTAssertFalse(prev)
        XCTAssertFalse(next)
    }
}
