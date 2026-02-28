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

    private static let tokenAwareInstruction = """
    CRITICAL: The text contains Slack emoji codes (e.g. :emoji_name:), @mentions, URLs, \
    file paths, and inline code. You MUST keep every one of these tokens exactly as it \
    appears — same spelling, punctuation, and position. Only fix the surrounding grammar \
    and spelling. Return only the corrected text.
    """

    static func appendTokenAwareInstruction(to systemPrompt: String) -> String {
        "\(systemPrompt)\n\n\(tokenAwareInstruction)"
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
        for token in tokens where restored.contains(token.placeholder) {
            restored = restored.replacingOccurrences(of: token.placeholder, with: token.originalToken)
        }
        return restored
    }

    /// Splits text into alternating text segments and token strings at token boundaries.
    /// Returns `textParts` (always one more than `tokens`) and the matched `tokens`.
    /// Example: "I am :sad: ok" → textParts: ["I am ", " ok"], tokens: [":sad:"]
    static func splitAroundTokens(in text: String) -> (textParts: [String], tokens: [String]) {
        let matches = tokenMatches(in: text)
        let nsText = text as NSString
        var textParts: [String] = []
        var tokenStrings: [String] = []
        var lastEnd = 0

        for match in matches {
            textParts.append(nsText.substring(with: NSRange(location: lastEnd, length: match.location - lastEnd)))
            tokenStrings.append(nsText.substring(with: match))
            lastEnd = match.location + match.length
        }
        textParts.append(nsText.substring(from: lastEnd))

        return (textParts: textParts, tokens: tokenStrings)
    }

    /// Reassembles corrected text parts with original tokens.
    /// `correctedParts` must have exactly one more element than `tokens`.
    static func reassemble(correctedParts: [String], tokens: [String]) -> String {
        var result = ""
        for i in 0..<tokens.count {
            result += correctedParts[i]
            result += tokens[i]
        }
        result += correctedParts[tokens.count]
        return result
    }

    /// Builds a token-free version of the text by removing all matched tokens.
    /// Each token is replaced by a single space to avoid merging surrounding words.
    static func stripTokens(from text: String) -> String {
        let matches = tokenMatches(in: text)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match, with: " ")
        }
        return mutable as String
    }

    /// Unicode Object Replacement Character used by rich-text editors (Slack, etc.)
    /// to represent inline images such as custom emojis.
    static let objectReplacementCharacter: Character = "\u{FFFC}"

    /// Recovers Slack emoji codes from HTML clipboard content.
    ///
    /// When Slack (and similar Electron apps) render custom emojis as inline images,
    /// the plain-text representation contains U+FFFC (￼) where each image was.
    /// The HTML clipboard preserves the emoji code in the `<img>` tag's `alt` attribute.
    ///
    /// This method extracts emoji codes from `<img>` tags in the HTML and replaces
    /// corresponding U+FFFC characters in the plain text.
    ///
    /// Returns the original text unchanged if recovery is not possible (no HTML,
    /// no U+FFFC, or count mismatch between U+FFFC and `<img>` tags).
    static func recoverObjectReplacements(in plainText: String, fromHTML html: String?) -> String {
        guard let html, plainText.contains(objectReplacementCharacter) else {
            return plainText
        }

        let imgAltValues = extractImgAltValues(from: html)
        let replacementCount = plainText.filter { $0 == objectReplacementCharacter }.count

        guard !imgAltValues.isEmpty, imgAltValues.count == replacementCount else {
            return plainText
        }

        var result = ""
        var altIndex = 0
        for char in plainText {
            if char == objectReplacementCharacter, altIndex < imgAltValues.count {
                result += imgAltValues[altIndex]
                altIndex += 1
            } else {
                result.append(char)
            }
        }

        return result
    }

    /// Extracts `alt` attribute values from `<img>` tags in HTML.
    static func extractImgAltValues(from html: String) -> [String] {
        let imgPattern = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive)
        let altPattern = try! NSRegularExpression(pattern: #"alt\s*=\s*"([^"]*)""#, options: .caseInsensitive)

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let imgMatches = imgPattern.matches(in: html, range: fullRange)

        var altValues: [String] = []
        for imgMatch in imgMatches {
            let imgTag = nsHTML.substring(with: imgMatch.range)
            let imgNS = imgTag as NSString
            let imgRange = NSRange(location: 0, length: imgNS.length)

            if let altMatch = altPattern.firstMatch(in: imgTag, range: imgRange),
               altMatch.numberOfRanges > 1 {
                altValues.append(imgNS.substring(with: altMatch.range(at: 1)))
            }
        }

        return altValues
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

    /// Returns the NSRanges of all recognized tokens in the text.
    static func tokenRanges(in text: String) -> [NSRange] {
        tokenMatches(in: text)
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
