import XCTest
@testable import GhostEditCore

final class LiveFeedbackStateMachineTests: XCTestCase {

    // MARK: - textChanged transitions

    func testIdleTextChangedStartsChecking() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .idle, event: .textChanged("Hello")
        )
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(effects, [.runSpellCheck("Hello")])
    }

    func testCheckingTextChangedRestartsChecking() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .textChanged("Updated")
        )
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(effects, [.runSpellCheck("Updated")])
    }

    func testCleanTextChangedStartsChecking() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .clean, event: .textChanged("New text")
        )
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(effects, [.runSpellCheck("New text")])
    }

    func testIssuesTextChangedStartsChecking() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .issues(3), event: .textChanged("Changed")
        )
        XCTAssertEqual(state, .checking)
        XCTAssertEqual(effects, [.runSpellCheck("Changed")])
    }

    // MARK: - textUnchanged transitions

    func testCheckingTextUnchangedStaysChecking() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .textUnchanged
        )
        XCTAssertEqual(state, .checking)
        XCTAssertTrue(effects.isEmpty)
    }

    func testIdleTextUnchangedStaysIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .idle, event: .textUnchanged
        )
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(effects.isEmpty)
    }

    func testCleanTextUnchangedStaysClean() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .clean, event: .textUnchanged
        )
        XCTAssertEqual(state, .clean)
        XCTAssertTrue(effects.isEmpty)
    }

    func testIssuesTextUnchangedStaysIssues() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .issues(2), event: .textUnchanged
        )
        XCTAssertEqual(state, .issues(2))
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - spellCheckComplete transitions

    func testCheckingSpellCheckNoIssuesGoesClean() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .spellCheckComplete([])
        )
        XCTAssertEqual(state, .clean)
        XCTAssertEqual(effects, [.clearUI])
    }

    func testCheckingSpellCheckWithIssuesGoesIssues() {
        let issues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"])
        ]
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .spellCheckComplete(issues)
        )
        XCTAssertEqual(state, .issues(1))
        XCTAssertEqual(effects, [.showIssues(issues)])
    }

    func testIdleSpellCheckCompleteUpdates() {
        let issues = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"]),
            SpellCheckIssue(word: "wrold", range: NSRange(location: 4, length: 5), kind: .spelling, suggestions: ["world"])
        ]
        let (state, _) = LiveFeedbackStateMachine.transition(
            state: .idle, event: .spellCheckComplete(issues)
        )
        XCTAssertEqual(state, .issues(2))
    }

    // MARK: - focusLost transitions

    func testCheckingFocusLostGoesIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .focusLost
        )
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(effects, [.clearUI])
    }

    func testIssuesFocusLostGoesIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .issues(5), event: .focusLost
        )
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(effects, [.clearUI])
    }

    func testIdleFocusLostStaysIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .idle, event: .focusLost
        )
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(effects, [.clearUI])
    }

    // MARK: - stopped transitions

    func testCheckingStoppedGoesIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .checking, event: .stopped
        )
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(effects, [.clearUI])
    }

    func testCleanStoppedGoesIdle() {
        let (state, effects) = LiveFeedbackStateMachine.transition(
            state: .clean, event: .stopped
        )
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(effects, [.clearUI])
    }

    // MARK: - isResultStale

    func testResultNotStale() {
        XCTAssertFalse(LiveFeedbackStateMachine.isResultStale(resultGeneration: 5, currentGeneration: 5))
    }

    func testResultStale() {
        XCTAssertTrue(LiveFeedbackStateMachine.isResultStale(resultGeneration: 4, currentGeneration: 5))
    }

    // MARK: - combineIssues

    func testCombineIssuesNoDuplicates() {
        let spell = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"])
        ]
        let model = [
            SpellCheckIssue(word: "wrold", range: NSRange(location: 10, length: 5), kind: .grammar, suggestions: ["world"])
        ]
        let result = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spell, modelIssues: model, ignoredWords: []
        )
        XCTAssertEqual(result.count, 2)
    }

    func testCombineIssuesDeduplicatesOverlapping() {
        let spell = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"])
        ]
        let model = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .grammar, suggestions: ["the"])
        ]
        let result = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spell, modelIssues: model, ignoredWords: []
        )
        XCTAssertEqual(result.count, 1)
    }

    func testCombineIssuesFiltersIgnoredWords() {
        let spell = [
            SpellCheckIssue(word: "teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"]),
            SpellCheckIssue(word: "ok", range: NSRange(location: 10, length: 2), kind: .spelling, suggestions: [])
        ]
        let result = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spell, modelIssues: [], ignoredWords: ["teh"]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].word, "ok")
    }

    func testCombineIssuesCaseInsensitiveIgnore() {
        let spell = [
            SpellCheckIssue(word: "Teh", range: NSRange(location: 0, length: 3), kind: .spelling, suggestions: ["the"])
        ]
        let result = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: spell, modelIssues: [], ignoredWords: ["teh"]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testCombineIssuesEmptyInputs() {
        let result = LiveFeedbackStateMachine.combineIssues(
            spellCheckIssues: [], modelIssues: [], ignoredWords: []
        )
        XCTAssertTrue(result.isEmpty)
    }
}
