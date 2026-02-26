import XCTest
@testable import GhostEditCore

final class SpellCheckSupportTests: XCTestCase {

    // MARK: - Constants

    func testDebounceIntervalIsPositive() {
        XCTAssertGreaterThan(SpellCheckSupport.debounceInterval, 0)
    }

    func testMaxDisplayIssuesIsPositive() {
        XCTAssertGreaterThan(SpellCheckSupport.maxDisplayIssues, 0)
    }

    func testMaxTextLengthIsPositive() {
        XCTAssertGreaterThan(SpellCheckSupport.maxTextLength, 0)
    }

    func testMinTextLengthIsPositive() {
        XCTAssertGreaterThan(SpellCheckSupport.minTextLength, 0)
    }

    func testMinTextLengthIsLessThanMax() {
        XCTAssertLessThan(SpellCheckSupport.minTextLength, SpellCheckSupport.maxTextLength)
    }

    // MARK: - summaryText

    func testSummaryTextEmptyIssues() {
        let result = SpellCheckSupport.summaryText(for: [])
        XCTAssertEqual(result, "No issues found")
    }

    func testSummaryTextSingleSpellingIssue() {
        let issues = [makeIssue(word: "teh", kind: .spelling)]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "1 spelling issue")
    }

    func testSummaryTextMultipleSpellingIssues() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "wrods", kind: .spelling),
            makeIssue(word: "speling", kind: .spelling),
        ]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "3 spelling issues")
    }

    func testSummaryTextSingleGrammarIssue() {
        let issues = [makeIssue(word: "their are", kind: .grammar)]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "1 grammar issue")
    }

    func testSummaryTextMultipleGrammarIssues() {
        let issues = [
            makeIssue(word: "their are", kind: .grammar),
            makeIssue(word: "he go", kind: .grammar),
        ]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "2 grammar issues")
    }

    func testSummaryTextMixedIssues() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "their are", kind: .grammar),
            makeIssue(word: "wrods", kind: .spelling),
        ]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "2 spelling issues, 1 grammar issue")
    }

    func testSummaryTextSingleStyleSuggestion() {
        let issues = [makeIssue(word: "\"", kind: .style)]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "1 style suggestion")
    }

    func testSummaryTextMultipleStyleSuggestions() {
        let issues = [
            makeIssue(word: "\"", kind: .style),
            makeIssue(word: "--", kind: .style),
        ]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "2 style suggestions")
    }

    func testSummaryTextMixedWithStyle() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "--", kind: .style),
            makeIssue(word: "their are", kind: .grammar),
        ]
        let result = SpellCheckSupport.summaryText(for: issues)
        XCTAssertEqual(result, "1 spelling issue, 1 grammar issue, 1 style suggestion")
    }

    // MARK: - filterIssues

    func testFilterIssuesEmptyIgnoredWords() {
        let issues = [makeIssue(word: "teh", kind: .spelling)]
        let result = SpellCheckSupport.filterIssues(issues, ignoredWords: [])
        XCTAssertEqual(result, issues)
    }

    func testFilterIssuesRemovesIgnoredWords() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "wrods", kind: .spelling),
        ]
        let result = SpellCheckSupport.filterIssues(issues, ignoredWords: ["teh"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].word, "wrods")
    }

    func testFilterIssuesCaseInsensitive() {
        let issues = [makeIssue(word: "Teh", kind: .spelling)]
        let result = SpellCheckSupport.filterIssues(issues, ignoredWords: ["teh"])
        XCTAssertEqual(result.count, 0)
    }

    func testFilterIssuesNoMatches() {
        let issues = [makeIssue(word: "teh", kind: .spelling)]
        let result = SpellCheckSupport.filterIssues(issues, ignoredWords: ["other"])
        XCTAssertEqual(result, issues)
    }

    func testFilterIssuesAllRemoved() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "wrods", kind: .spelling),
        ]
        let result = SpellCheckSupport.filterIssues(issues, ignoredWords: ["teh", "wrods"])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterIssuesEmptyIssuesArray() {
        let result = SpellCheckSupport.filterIssues([], ignoredWords: ["teh"])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - truncateForDisplay

    func testTruncateForDisplayWithinLimit() {
        let issues = (0..<5).map { makeIssue(word: "word\($0)", kind: .spelling) }
        let result = SpellCheckSupport.truncateForDisplay(issues)
        XCTAssertEqual(result.count, 5)
    }

    func testTruncateForDisplayExceedsLimit() {
        let issues = (0..<30).map { makeIssue(word: "word\($0)", kind: .spelling) }
        let result = SpellCheckSupport.truncateForDisplay(issues)
        XCTAssertEqual(result.count, SpellCheckSupport.maxDisplayIssues)
    }

    func testTruncateForDisplayEmpty() {
        let result = SpellCheckSupport.truncateForDisplay([])
        XCTAssertTrue(result.isEmpty)
    }

    func testTruncateForDisplayExactlyAtLimit() {
        let issues = (0..<SpellCheckSupport.maxDisplayIssues).map {
            makeIssue(word: "word\($0)", kind: .spelling)
        }
        let result = SpellCheckSupport.truncateForDisplay(issues)
        XCTAssertEqual(result.count, SpellCheckSupport.maxDisplayIssues)
    }

    // MARK: - shouldCheck

    func testShouldCheckNormalText() {
        XCTAssertTrue(SpellCheckSupport.shouldCheck(text: "Hello world"))
    }

    func testShouldCheckEmptyText() {
        XCTAssertFalse(SpellCheckSupport.shouldCheck(text: ""))
    }

    func testShouldCheckSingleCharacter() {
        XCTAssertFalse(SpellCheckSupport.shouldCheck(text: "a"))
    }

    func testShouldCheckMinLengthText() {
        let text = String(repeating: "a", count: SpellCheckSupport.minTextLength)
        XCTAssertTrue(SpellCheckSupport.shouldCheck(text: text))
    }

    func testShouldCheckTextAtMaxLength() {
        let text = String(repeating: "a", count: SpellCheckSupport.maxTextLength)
        XCTAssertTrue(SpellCheckSupport.shouldCheck(text: text))
    }

    func testShouldCheckTextExceedsMaxLength() {
        let text = String(repeating: "a", count: SpellCheckSupport.maxTextLength + 1)
        XCTAssertFalse(SpellCheckSupport.shouldCheck(text: text))
    }

    // MARK: - issuesByKind

    func testIssuesByKindEmpty() {
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind([])
        XCTAssertTrue(spelling.isEmpty)
        XCTAssertTrue(grammar.isEmpty)
        XCTAssertTrue(style.isEmpty)
    }

    func testIssuesByKindAllSpelling() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "wrods", kind: .spelling),
        ]
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind(issues)
        XCTAssertEqual(spelling.count, 2)
        XCTAssertTrue(grammar.isEmpty)
        XCTAssertTrue(style.isEmpty)
    }

    func testIssuesByKindAllGrammar() {
        let issues = [
            makeIssue(word: "their are", kind: .grammar),
            makeIssue(word: "he go", kind: .grammar),
        ]
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind(issues)
        XCTAssertTrue(spelling.isEmpty)
        XCTAssertEqual(grammar.count, 2)
        XCTAssertTrue(style.isEmpty)
    }

    func testIssuesByKindAllStyle() {
        let issues = [
            makeIssue(word: "\"", kind: .style),
            makeIssue(word: "--", kind: .style),
        ]
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind(issues)
        XCTAssertTrue(spelling.isEmpty)
        XCTAssertTrue(grammar.isEmpty)
        XCTAssertEqual(style.count, 2)
    }

    func testIssuesByKindMixed() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "their are", kind: .grammar),
            makeIssue(word: "wrods", kind: .spelling),
        ]
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind(issues)
        XCTAssertEqual(spelling.count, 2)
        XCTAssertEqual(grammar.count, 1)
        XCTAssertTrue(style.isEmpty)
    }

    func testIssuesByKindMixedWithStyle() {
        let issues = [
            makeIssue(word: "teh", kind: .spelling),
            makeIssue(word: "--", kind: .style),
            makeIssue(word: "their are", kind: .grammar),
        ]
        let (spelling, grammar, style) = SpellCheckSupport.issuesByKind(issues)
        XCTAssertEqual(spelling.count, 1)
        XCTAssertEqual(grammar.count, 1)
        XCTAssertEqual(style.count, 1)
    }

    // MARK: - issueDescription

    func testIssueDescriptionSpellingWithSuggestions() {
        let issue = SpellCheckIssue(
            word: "teh",
            range: NSRange(location: 0, length: 3),
            kind: .spelling,
            suggestions: ["the", "tea"]
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Spelling: \"teh\" → \"the\"")
    }

    func testIssueDescriptionGrammarWithSuggestions() {
        let issue = SpellCheckIssue(
            word: "their are",
            range: NSRange(location: 0, length: 9),
            kind: .grammar,
            suggestions: ["there are"]
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Grammar: \"their are\" → \"there are\"")
    }

    func testIssueDescriptionNoSuggestions() {
        let issue = SpellCheckIssue(
            word: "xyz",
            range: NSRange(location: 0, length: 3),
            kind: .spelling,
            suggestions: []
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Spelling: \"xyz\"")
    }

    func testIssueDescriptionGrammarNoSuggestions() {
        let issue = SpellCheckIssue(
            word: "bad grammar",
            range: NSRange(location: 0, length: 11),
            kind: .grammar,
            suggestions: []
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Grammar: \"bad grammar\"")
    }

    func testIssueDescriptionStyleWithSuggestion() {
        let issue = SpellCheckIssue(
            word: "--",
            range: NSRange(location: 0, length: 2),
            kind: .style,
            suggestions: ["—"]
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Style: \"--\" → \"—\"")
    }

    func testIssueDescriptionStyleNoSuggestions() {
        let issue = SpellCheckIssue(
            word: "(c)",
            range: NSRange(location: 0, length: 3),
            kind: .style,
            suggestions: []
        )
        let result = SpellCheckSupport.issueDescription(for: issue)
        XCTAssertEqual(result, "Style: \"(c)\"")
    }

    // MARK: - SpellCheckIssue Equatable

    func testSpellCheckIssueEquatable() {
        let a = makeIssue(word: "teh", kind: .spelling)
        let b = makeIssue(word: "teh", kind: .spelling)
        let c = makeIssue(word: "wrods", kind: .spelling)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSpellCheckIssueKindEquatable() {
        XCTAssertEqual(SpellCheckIssue.Kind.spelling, SpellCheckIssue.Kind.spelling)
        XCTAssertEqual(SpellCheckIssue.Kind.grammar, SpellCheckIssue.Kind.grammar)
        XCTAssertEqual(SpellCheckIssue.Kind.style, SpellCheckIssue.Kind.style)
        XCTAssertNotEqual(SpellCheckIssue.Kind.spelling, SpellCheckIssue.Kind.grammar)
        XCTAssertNotEqual(SpellCheckIssue.Kind.spelling, SpellCheckIssue.Kind.style)
        XCTAssertNotEqual(SpellCheckIssue.Kind.grammar, SpellCheckIssue.Kind.style)
    }

    func testSpellCheckIssueKindRawValues() {
        XCTAssertEqual(SpellCheckIssue.Kind.spelling.rawValue, "spelling")
        XCTAssertEqual(SpellCheckIssue.Kind.grammar.rawValue, "grammar")
        XCTAssertEqual(SpellCheckIssue.Kind.style.rawValue, "style")
    }

    // MARK: - Helpers

    private func makeIssue(word: String, kind: SpellCheckIssue.Kind) -> SpellCheckIssue {
        let suggestions: [String]
        switch kind {
        case .spelling: suggestions = ["fixed"]
        case .grammar: suggestions = []
        case .style: suggestions = ["replaced"]
        }
        return SpellCheckIssue(
            word: word,
            range: NSRange(location: 0, length: word.count),
            kind: kind,
            suggestions: suggestions
        )
    }
}
