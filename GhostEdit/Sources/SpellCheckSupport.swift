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

    /// Returns true if the word looks like a proper noun (capitalized, not sentence-start).
    /// A word is considered a likely proper noun if it starts with an uppercase letter
    /// followed by lowercase letters, and is not at the very start of the text.
    static func isLikelyProperNoun(_ word: String, at range: NSRange, in text: String) -> Bool {
        guard let first = word.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else {
            return false
        }
        // Single letters and all-caps words (acronyms) are not proper nouns
        let restOfWord = word.dropFirst()
        if restOfWord.isEmpty || restOfWord.allSatisfy({ $0.isUppercase }) {
            return false
        }
        // If at text start, it's just normal capitalization
        if range.location == 0 { return false }
        // Check if preceded by sentence-ending punctuation + space
        let nsText = text as NSString
        let beforeIdx = range.location - 1
        guard beforeIdx >= 0 else { return false }
        // Walk backwards to find the first non-whitespace character
        var idx = beforeIdx
        while idx >= 0 && CharacterSet.whitespaces.contains(
            Unicode.Scalar(nsText.character(at: idx))!
        ) {
            idx -= 1
        }
        guard idx >= 0 else { return false }
        let precedingChar = Unicode.Scalar(nsText.character(at: idx))!
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        // If preceded by a sentence ender, this is just normal sentence-start capitalization
        if sentenceEnders.contains(precedingChar) { return false }
        // Capitalized mid-sentence → likely a proper noun
        return true
    }

    /// Filters out issues where the flagged word is likely a proper noun (name).
    static func filterProperNouns(
        _ issues: [SpellCheckIssue],
        in text: String
    ) -> [SpellCheckIssue] {
        issues.filter { issue in
            guard issue.kind == .spelling else { return true }
            return !isLikelyProperNoun(issue.word, at: issue.range, in: text)
        }
    }

    /// Returns true if the word looks like an acronym/abbreviation (2+ uppercase letters).
    static func isLikelyAcronym(_ word: String) -> Bool {
        guard word.count >= 2 else { return false }
        return word.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    /// Filters out spelling issues where the flagged word is likely an acronym.
    static func filterAcronyms(_ issues: [SpellCheckIssue]) -> [SpellCheckIssue] {
        issues.filter { issue in
            guard issue.kind == .spelling else { return true }
            return !isLikelyAcronym(issue.word)
        }
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

    // MARK: - Icon

    /// Returns the SF Symbol name for the given issue kind.
    static func iconName(for kind: SpellCheckIssue.Kind) -> String {
        switch kind {
        case .spelling: return "textformat.abc.dottedunderline"
        case .grammar: return "text.badge.xmark"
        case .style: return "paintbrush.pointed"
        }
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
