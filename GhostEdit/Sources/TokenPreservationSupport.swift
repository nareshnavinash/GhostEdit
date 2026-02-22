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
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #":[A-Za-z0-9_+\-]+:|@<[^>\s]+>"#
    )

    private static let promptInstruction = """
    Important token-preservation rule:
    - You may receive placeholders like __GHOSTEDIT_KEEP_0__ that represent Slack mentions/emojis.
    - Keep every placeholder exactly unchanged (same spelling, case, and punctuation).
    - Do not remove, reorder, duplicate, split, or edit placeholders.
    Return only the corrected text.
    """

    static func protectTokens(in text: String) -> TokenProtectionResult {
        let nsText = text as NSString
        let matches = tokenRegex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )

        guard !matches.isEmpty else {
            return TokenProtectionResult(protectedText: text, tokens: [])
        }

        var usedPlaceholders = Set<String>()
        var replacements: [(range: NSRange, token: ProtectedToken)] = []

        for (index, match) in matches.enumerated() {
            let originalToken = nsText.substring(with: match.range)
            let placeholder = uniquePlaceholder(for: index, originalText: text, used: &usedPlaceholders)
            replacements.append((
                range: match.range,
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
}
