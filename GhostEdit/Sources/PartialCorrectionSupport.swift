import Foundation

enum PartialCorrectionSupport {
    /// Split text into sentences, preserving original spacing between them.
    /// Returns an array of (sentence, trailingWhitespace) tuples.
    static func splitIntoSentences(_ text: String) -> [(sentence: String, trailing: String)] {
        guard !text.isEmpty else { return [] }

        var results: [(sentence: String, trailing: String)] = []
        var current = ""
        var trailing = ""
        var afterSentenceEnd = false

        for char in text {
            if afterSentenceEnd {
                if char.isWhitespace {
                    trailing.append(char)
                } else {
                    results.append((sentence: current, trailing: trailing))
                    current = String(char)
                    trailing = ""
                    afterSentenceEnd = false
                }
            } else {
                current.append(char)
                if isSentenceTerminator(char) {
                    afterSentenceEnd = true
                }
            }
        }

        if !current.isEmpty {
            results.append((sentence: current, trailing: trailing))
        }

        return results
    }

    /// Reassemble sentence parts into a single text.
    static func reassemble(_ parts: [(sentence: String, trailing: String)]) -> String {
        parts.map { $0.sentence + $0.trailing }.joined()
    }

    /// Returns `true` if the sentence looks like it may need correction
    /// (simple heuristic: contains a lowercase start after whitespace, or is just unchanged).
    static func sentenceNeedsCorrection(original: String, corrected: String) -> Bool {
        let trimOrig = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimCorr = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimOrig != trimCorr
    }

    private static func isSentenceTerminator(_ char: Character) -> Bool {
        char == "." || char == "!" || char == "?"
    }
}
