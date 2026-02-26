import Foundation
import CHarperBridge

private struct HarperLintJSON: Decodable {
    let word: String
    let start: Int
    let end: Int
    let kind: String
    let message: String
    let suggestions: [String]
}

enum HarperLinter {
    /// Lint text using Harper and return SpellCheckIssues.
    static func lint(_ text: String) -> [SpellCheckIssue] {
        guard let cString = text.cString(using: .utf8) else { return [] }

        guard let resultPtr = harper_lint(cString) else { return [] }
        let json = String(cString: resultPtr)
        harper_free_string(resultPtr)

        guard let data = json.data(using: .utf8) else { return [] }
        guard let lints = try? JSONDecoder().decode([HarperLintJSON].self, from: data) else {
            return []
        }

        let nsText = text as NSString

        return lints.compactMap { lint in
            // Harper returns byte offsets — convert to NSString (UTF-16) range
            guard let startIndex = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: lint.start,
                limitedBy: text.utf8.endIndex
            ) else { return nil }
            guard let endIndex = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: lint.end,
                limitedBy: text.utf8.endIndex
            ) else { return nil }

            let swiftRange = startIndex ..< endIndex
            let nsRange = NSRange(swiftRange, in: text)
            guard nsRange.location + nsRange.length <= nsText.length else { return nil }

            let kind: SpellCheckIssue.Kind
            switch lint.kind {
            case "spelling": kind = .spelling
            case "grammar": kind = .grammar
            default: kind = .style
            }

            return SpellCheckIssue(
                word: lint.word,
                range: nsRange,
                kind: kind,
                suggestions: lint.suggestions
            )
        }
    }
}
