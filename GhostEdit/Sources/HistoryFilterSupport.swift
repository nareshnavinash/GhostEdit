import Foundation

enum HistoryFilterSupport {
    /// Apply status filter to history entries.
    /// filter: 0=all, 1=success only, 2=failed only
    static func applyStatusFilter(_ entries: [CorrectionHistoryEntry], filter: Int) -> [CorrectionHistoryEntry] {
        switch filter {
        case 1: return entries.filter { $0.succeeded }
        case 2: return entries.filter { !$0.succeeded }
        default: return entries
        }
    }

    /// Apply case-insensitive search filter across original, generated, provider, model fields.
    static func applySearchFilter(
        _ entries: [(entry: CorrectionHistoryEntry, original: String, generated: String, provider: String, model: String)],
        query: String
    ) -> [(entry: CorrectionHistoryEntry, original: String, generated: String, provider: String, model: String)] {
        guard !query.isEmpty else { return entries }
        let lowered = query.lowercased()
        return entries.filter { item in
            item.original.lowercased().contains(lowered)
                || item.generated.lowercased().contains(lowered)
                || item.provider.lowercased().contains(lowered)
                || item.model.lowercased().contains(lowered)
        }
    }

    /// Format a date as a relative timestamp.
    /// Uses injected formatters for testability.
    static func relativeTimestamp(
        for date: Date,
        now: Date,
        timeOnlyFormatter: (Date) -> String,
        fullFormatter: (Date) -> String
    ) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) min\(mins == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 172800 {
            let timeStr = timeOnlyFormatter(date)
            return "Yesterday at \(timeStr)"
        } else {
            return fullFormatter(date)
        }
    }

    /// Color name for a correction duration in milliseconds.
    /// < 2000ms = green, < 5000ms = orange, >= 5000ms = red.
    static func durationColorName(milliseconds: Int) -> String {
        if milliseconds < 2000 {
            return "systemGreen"
        } else if milliseconds < 5000 {
            return "systemOrange"
        } else {
            return "systemRed"
        }
    }
}
