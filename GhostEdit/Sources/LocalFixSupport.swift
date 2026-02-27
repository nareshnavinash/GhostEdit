import Foundation

enum LocalFixSupport {
    /// Extract the line of text at a given cursor location from a larger text string.
    /// Returns the line text (without trailing newline) and its NSRange within the original text.
    static func extractLineAtCursor(text: String, cursorLocation: Int) -> (lineText: String, lineRange: NSRange)? {
        let nsText = text as NSString
        let clampedLocation = max(0, min(cursorLocation, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: clampedLocation, length: 0))
        guard lineRange.length > 0 else { return nil }
        var lineText = nsText.substring(with: lineRange)
        // Trim trailing newline for correction but preserve range for reconstruction
        if lineText.hasSuffix("\n") {
            lineText = String(lineText.dropLast())
        }
        guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (lineText, lineRange)
    }

    /// Merge Harper linter issues with NSSpellChecker issues, removing overlapping ranges.
    /// Also filters proper nouns, acronyms, and truncates for display.
    static func mergeIssues(harper: [SpellCheckIssue], nsChecker: [SpellCheckIssue], text: String) -> [SpellCheckIssue] {
        var merged = harper
        for nsIssue in nsChecker {
            let overlaps = harper.contains { h in
                h.range.intersection(nsIssue.range) != nil
            }
            if !overlaps {
                merged.append(nsIssue)
            }
        }
        // Filter out likely proper nouns (names) and acronyms from spelling issues
        merged = SpellCheckSupport.filterProperNouns(merged, in: text)
        merged = SpellCheckSupport.filterAcronyms(merged)
        return SpellCheckSupport.truncateForDisplay(merged)
    }
}
