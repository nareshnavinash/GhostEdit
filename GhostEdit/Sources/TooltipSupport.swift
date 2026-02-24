import Foundation

enum TooltipSupport {
    static let defaultTooltip = "GhostEdit"

    /// Build a tooltip string summarizing the last correction result.
    static func tooltip(
        lastOriginal: String?,
        lastCorrected: String?,
        lastTime: Date?,
        provider: String?,
        model: String?,
        timeFormatter: DateFormatter? = nil
    ) -> String {
        guard let original = lastOriginal,
              let corrected = lastCorrected,
              !original.isEmpty
        else {
            return defaultTooltip
        }

        var parts: [String] = ["GhostEdit"]

        if let time = lastTime {
            let formatter = timeFormatter ?? Self.defaultTimeFormatter
            parts.append("Last: \(formatter.string(from: time))")
        }

        let preview = truncatePreview(corrected, maxLength: 60)
        parts.append(preview)

        if let provider = provider, !provider.isEmpty {
            let modelInfo = (model != nil && !model!.isEmpty) ? " (\(model!))" : ""
            parts.append("via \(provider)\(modelInfo)")
        }

        return parts.joined(separator: "\n")
    }

    /// Truncate text for tooltip display, appending ellipsis if needed.
    static func truncatePreview(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        guard singleLine.count > maxLength else {
            return singleLine
        }
        let prefix = singleLine.prefix(maxLength - 1)
        return "\(prefix)…"
    }

    private static let defaultTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
