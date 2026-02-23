import Foundation

struct ProtectedToken: Equatable {
    let placeholder: String
    let originalToken: String
}

struct TokenProtectionResult: Equatable {
    let protectedText: String
    let tokens: [ProtectedToken]

    var hasProtectedTokens: Bool {
        !tokens.isEmpty
    }
}

enum TokenPreservationSupport {
    private static let placeholderPrefix = "__GHOSTEDIT_KEEP_"
    private static let tokenPatterns = [
        #"`[^`\n]+`"#,                                           // Inline code
        #"https?://[^\s<>()]+[^\s<>()\.,;:!?]"#,               // URLs
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,  // Email addresses
        #"(?:~|/|\.{1,2}/)(?:[A-Za-z0-9._\-]+/)*[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?"#, // Absolute/relative file paths
        #"(?:[A-Za-z0-9._\-]+/){1,}[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?"#,               // Folder/file-style paths
        #":[A-Za-z0-9_+\-]+:"#,                                  // Slack emojis
        #"(?<![\w@])@<[^>\s]+>"#,                               // @<id>
        #"(?<![\w@])<@[A-Za-z0-9][A-Za-z0-9._\-]*>"#,          // <@id>
        #"(?<![\w@])@[A-Za-z0-9](?:[A-Za-z0-9._\-]*[A-Za-z0-9_\-])?"# // @name
    ]
    private static let tokenRegexes: [NSRegularExpression] = tokenPatterns.map { pattern in
        try! NSRegularExpression(pattern: pattern)
    }

    private static let promptInstruction = """
    Important token-preservation rule:
    - You may receive placeholders like __GHOSTEDIT_KEEP_0__ that represent mentions, emojis, URLs, emails, file paths, or inline code.
    - Keep every placeholder exactly unchanged (same spelling, case, and punctuation).
    - Do not remove, reorder, duplicate, split, or edit placeholders.
    Return only the corrected text.
    """

    static func protectTokens(in text: String) -> TokenProtectionResult {
        let nsText = text as NSString
        let matches = tokenMatches(in: text)

        guard !matches.isEmpty else {
            return TokenProtectionResult(protectedText: text, tokens: [])
        }

        var usedPlaceholders = Set<String>()
        var replacements: [(range: NSRange, token: ProtectedToken)] = []

        for (index, match) in matches.enumerated() {
            let originalToken = nsText.substring(with: match)
            let placeholder = uniquePlaceholder(for: index, originalText: text, used: &usedPlaceholders)
            replacements.append((
                range: match,
                token: ProtectedToken(placeholder: placeholder, originalToken: originalToken)
            ))
        }

        let mutable = NSMutableString(string: text)
        for replacement in replacements.reversed() {
            mutable.replaceCharacters(in: replacement.range, with: replacement.token.placeholder)
        }

        return TokenProtectionResult(
            protectedText: mutable as String,
            tokens: replacements.map(\.token)
        )
    }

    static func appendInstruction(to systemPrompt: String) -> String {
        "\(systemPrompt)\n\n\(promptInstruction)"
    }

    static func placeholdersAreIntact(in output: String, tokens: [ProtectedToken]) -> Bool {
        for token in tokens {
            let occurrences = output.components(separatedBy: token.placeholder).count - 1
            if occurrences != 1 {
                return false
            }
        }
        return true
    }

    static func restoreTokens(in output: String, tokens: [ProtectedToken]) -> String {
        var restored = output
        for token in tokens {
            restored = restored.replacingOccurrences(of: token.placeholder, with: token.originalToken)
        }
        return restored
    }

    /// Best-effort restoration: restores any placeholders that survived the AI round-trip.
    /// Placeholders the AI removed are simply absent from the result.
    static func bestEffortRestore(in output: String, tokens: [ProtectedToken]) -> String {
        var restored = output
        for token in tokens {
            if restored.contains(token.placeholder) {
                restored = restored.replacingOccurrences(of: token.placeholder, with: token.originalToken)
            }
        }
        return restored
    }

    private static func uniquePlaceholder(
        for index: Int,
        originalText: String,
        used: inout Set<String>
    ) -> String {
        var suffix = 0
        var candidate = "\(placeholderPrefix)\(index)__"

        while originalText.contains(candidate) || used.contains(candidate) {
            suffix += 1
            candidate = "\(placeholderPrefix)\(index)_\(suffix)__"
        }

        used.insert(candidate)
        return candidate
    }

    private static func tokenMatches(in text: String) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var candidates: [(range: NSRange, priority: Int)] = []

        for (priority, regex) in tokenRegexes.enumerated() {
            for match in regex.matches(in: text, range: fullRange) where match.range.length > 0 {
                candidates.append((range: match.range, priority: priority))
            }
        }

        guard !candidates.isEmpty else {
            return []
        }

        candidates.sort { lhs, rhs in
            let lhsKey = (lhs.range.location, -lhs.range.length, lhs.priority)
            let rhsKey = (rhs.range.location, -rhs.range.length, rhs.priority)
            return lhsKey < rhsKey
        }

        var selected: [NSRange] = []
        var selectedEnd = 0

        for candidate in candidates {
            let range = candidate.range
            let start = range.location
            let end = range.location + range.length

            if selected.isEmpty || start >= selectedEnd {
                selected.append(range)
                selectedEnd = end
            }
        }

        return selected
    }
}
