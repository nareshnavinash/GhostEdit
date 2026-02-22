import Foundation

struct WritingCoachInsights: Equatable {
    var positives: [String]
    var improvements: [String]

    var hasContent: Bool {
        !positives.isEmpty || !improvements.isEmpty
    }
}

enum WritingCoachSupport {
    private enum Section {
        case positives
        case improvements
    }

    private struct Payload: Decodable {
        let positives: [String]
        let improvements: [String]
    }

    static let systemPrompt = """
    You are a writing coach. Analyze the writing samples and return only valid JSON with this exact schema:
    {"positives":["..."],"improvements":["..."]}
    Requirements:
    - Positives: highlight recurring strengths in tone, structure, and clarity.
    - Improvements: give concrete, professional next-step suggestions.
    - Keep each item concise and actionable.
    - Do not include markdown, comments, or extra keys.
    """

    static func buildInput(from originalTexts: [String]) -> String {
        let cleaned = originalTexts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            return "No writing samples were provided."
        }

        let samples = cleaned.enumerated().map { index, text in
            """
            Sample \(index + 1):
            \(text)
            """
        }.joined(separator: "\n\n---\n\n")

        return "Analyze these writing samples from one author:\n\n\(samples)"
    }

    static func parseInsights(from response: String) -> WritingCoachInsights? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let decoded = parseJSONPayload(from: trimmed), decoded.hasContent {
            return decoded
        }

        let fallback = parseBulletSections(from: trimmed)
        return fallback.hasContent ? fallback : nil
    }

    static func popupText(for insights: WritingCoachInsights, sampleCount: Int) -> String {
        let positives = numberedLines(from: insights.positives, emptyFallback: "No recurring strengths detected yet.")
        let improvements = numberedLines(from: insights.improvements, emptyFallback: "No specific improvements suggested yet.")

        return """
        Reviewed \(sampleCount) writing sample(s).

        Positives
        \(positives)

        Improvements
        \(improvements)
        """
    }

    private static func parseJSONPayload(from text: String) -> WritingCoachInsights? {
        let data = Data(text.utf8)

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        return WritingCoachInsights(
            positives: normalize(payload.positives),
            improvements: normalize(payload.improvements)
        )
    }

    private static func parseBulletSections(from text: String) -> WritingCoachInsights {
        var positives: [String] = []
        var improvements: [String] = []
        var section: Section?

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let lowered = trimmed.lowercased()
            if lowered.contains("positive") || lowered.contains("strength") {
                section = .positives
                continue
            }

            if lowered.contains("improvement") || lowered.contains("improve") || lowered.contains("recommendation") {
                section = .improvements
                continue
            }

            guard let item = listItemText(from: trimmed) else {
                continue
            }

            switch section {
            case .positives:
                positives.append(item)
            case .improvements:
                improvements.append(item)
            case .none:
                improvements.append(item)
            }
        }

        return WritingCoachInsights(
            positives: normalize(positives),
            improvements: normalize(improvements)
        )
    }

    private static func listItemText(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count, CharacterSet.decimalDigits.contains(scalars[index]) {
            index += 1
        }

        guard index > 0, index + 1 < scalars.count else {
            return nil
        }

        let marker = scalars[index]
        let separator = scalars[index + 1]
        guard (marker == "." || marker == ")"), separator == " " else {
            return nil
        }

        let start = line.index(line.startIndex, offsetBy: index + 2)
        return String(line[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func numberedLines(from values: [String], emptyFallback: String) -> String {
        if values.isEmpty {
            return "1. \(emptyFallback)"
        }

        return values.enumerated().map { index, value in
            "\(index + 1). \(value)"
        }.joined(separator: "\n")
    }
}
