import Foundation

struct SpellCheckIssue: Equatable {
    enum Kind: String, Equatable {
        case spelling
        case grammar
        case style
    }

    let word: String
    let range: NSRange
    let kind: Kind
    let suggestions: [String]
}

enum SpellCheckSupport {
    // MARK: - Constants

    /// Debounce interval between text changes and spell check.
    static let debounceInterval: TimeInterval = 0.5

    /// Maximum number of issues to display in the widget popover.
    static let maxDisplayIssues: Int = 20

    /// Maximum text length to check (longer texts are skipped for performance).
    static let maxTextLength: Int = 10_000

    /// Minimum text length to bother checking.
    static let minTextLength: Int = 2

    // MARK: - Summary

    /// Returns a human-readable summary of the issues found.
    static func summaryText(for issues: [SpellCheckIssue]) -> String {
        guard !issues.isEmpty else {
            return "No issues found"
        }

        let (spelling, grammar, style) = issuesByKind(issues)

        var parts: [String] = []
        if !spelling.isEmpty {
            parts.append(spelling.count == 1 ? "1 spelling issue" : "\(spelling.count) spelling issues")
        }
        if !grammar.isEmpty {
            parts.append(grammar.count == 1 ? "1 grammar issue" : "\(grammar.count) grammar issues")
        }
        if !style.isEmpty {
            parts.append(style.count == 1 ? "1 style suggestion" : "\(style.count) style suggestions")
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Filtering

    /// Filters out issues for words the user has chosen to ignore.
    static func filterIssues(
        _ issues: [SpellCheckIssue],
        ignoredWords: Set<String>
    ) -> [SpellCheckIssue] {
        guard !ignoredWords.isEmpty else { return issues }
        return issues.filter { !ignoredWords.contains($0.word.lowercased()) }
    }

    /// Limits display to the configured maximum.
    static func truncateForDisplay(_ issues: [SpellCheckIssue]) -> [SpellCheckIssue] {
        Array(issues.prefix(maxDisplayIssues))
    }

    // MARK: - Validation

    /// Whether the given text is eligible for spell checking.
    static func shouldCheck(text: String) -> Bool {
        let length = text.count
        return length >= minTextLength && length <= maxTextLength
    }

    // MARK: - Partitioning

    /// Partition issues by kind.
    static func issuesByKind(
        _ issues: [SpellCheckIssue]
    ) -> (spelling: [SpellCheckIssue], grammar: [SpellCheckIssue], style: [SpellCheckIssue]) {
        var spelling: [SpellCheckIssue] = []
        var grammar: [SpellCheckIssue] = []
        var style: [SpellCheckIssue] = []
        for issue in issues {
            switch issue.kind {
            case .spelling:
                spelling.append(issue)
            case .grammar:
                grammar.append(issue)
            case .style:
                style.append(issue)
            }
        }
        return (spelling, grammar, style)
    }

    // MARK: - Issue description

    /// Returns a human-readable description of a single issue for display.
    static func issueDescription(for issue: SpellCheckIssue) -> String {
        let kindLabel: String
        switch issue.kind {
        case .spelling: kindLabel = "Spelling"
        case .grammar: kindLabel = "Grammar"
        case .style: kindLabel = "Style"
        }
        if issue.suggestions.isEmpty {
            return "\(kindLabel): \"\(issue.word)\""
        }
        let topSuggestion = issue.suggestions[0]
        return "\(kindLabel): \"\(issue.word)\" → \"\(topSuggestion)\""
    }
}
