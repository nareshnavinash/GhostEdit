import Foundation

enum HistoryCSVExporter {
    private static let headers = [
        "Timestamp",
        "Status",
        "Provider",
        "Model",
        "Duration (ms)",
        "Original Text",
        "Generated Text"
    ]

    static func csv(
        entries: [CorrectionHistoryEntry],
        timestampFormatter: (Date) -> String
    ) -> String {
        var lines: [String] = [serializedRow(headers)]
        lines.reserveCapacity(entries.count + 1)

        for entry in entries {
            let fields = [
                timestampFormatter(entry.timestamp),
                entry.succeeded ? "Succeeded" : "Failed",
                entry.provider,
                entry.model,
                "\(entry.durationMilliseconds)",
                entry.originalText,
                entry.generatedText
            ]
            lines.append(serializedRow(fields))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializedRow(_ fields: [String]) -> String {
        fields.map(csvEscaped).joined(separator: ",")
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(where: requiresEscapingCharacter) else {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func requiresEscapingCharacter(_ character: Character) -> Bool {
        character == "," || character == "\"" || character == "\n" || character == "\r"
    }
}
