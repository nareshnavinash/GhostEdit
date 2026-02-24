import Foundation

struct CorrectionStatistics: Equatable {
    let totalCorrections: Int
    let successCount: Int
    let failureCount: Int
    let averageDurationMilliseconds: Int
    let totalCharactersCorrected: Int
    let longestCorrectionCharacters: Int
    let providerBreakdown: [String: Int]
    let modelBreakdown: [String: Int]
    let successRate: Double

    var averageDurationFormatted: String {
        if averageDurationMilliseconds < 1_000 {
            return "\(averageDurationMilliseconds)ms"
        }
        let seconds = Double(averageDurationMilliseconds) / 1_000.0
        return String(format: "%.1fs", seconds)
    }
}

enum CorrectionStatisticsSupport {
    static func compute(from entries: [CorrectionHistoryEntry]) -> CorrectionStatistics {
        guard !entries.isEmpty else {
            return CorrectionStatistics(
                totalCorrections: 0,
                successCount: 0,
                failureCount: 0,
                averageDurationMilliseconds: 0,
                totalCharactersCorrected: 0,
                longestCorrectionCharacters: 0,
                providerBreakdown: [:],
                modelBreakdown: [:],
                successRate: 0
            )
        }

        let successEntries = entries.filter(\.succeeded)
        let failureCount = entries.count - successEntries.count
        let totalDuration = entries.reduce(0) { $0 + $1.durationMilliseconds }
        let avgDuration = totalDuration / entries.count

        let totalChars = successEntries.reduce(0) { $0 + $1.originalText.count }
        let longestChars = successEntries.map(\.originalText.count).max() ?? 0

        var providerBreakdown: [String: Int] = [:]
        var modelBreakdown: [String: Int] = [:]
        for entry in entries {
            providerBreakdown[entry.provider, default: 0] += 1
            modelBreakdown[entry.model, default: 0] += 1
        }

        let successRate = Double(successEntries.count) / Double(entries.count)

        return CorrectionStatistics(
            totalCorrections: entries.count,
            successCount: successEntries.count,
            failureCount: failureCount,
            averageDurationMilliseconds: avgDuration,
            totalCharactersCorrected: totalChars,
            longestCorrectionCharacters: longestChars,
            providerBreakdown: providerBreakdown,
            modelBreakdown: modelBreakdown,
            successRate: successRate
        )
    }

    /// Format statistics as a multi-line summary for display.
    static func formattedSummary(_ stats: CorrectionStatistics) -> String {
        var lines: [String] = []
        lines.append("Total corrections: \(stats.totalCorrections)")
        lines.append("Successful: \(stats.successCount)")
        lines.append("Failed: \(stats.failureCount)")
        lines.append("Success rate: \(formatPercent(stats.successRate))")
        lines.append("Average duration: \(stats.averageDurationFormatted)")
        lines.append("Total characters corrected: \(stats.totalCharactersCorrected)")
        lines.append("Longest correction: \(stats.longestCorrectionCharacters) characters")

        if !stats.providerBreakdown.isEmpty {
            lines.append("")
            lines.append("By provider:")
            for (provider, count) in sortedBreakdown(stats.providerBreakdown) {
                lines.append("  \(provider): \(count)")
            }
        }

        if !stats.modelBreakdown.isEmpty {
            lines.append("")
            lines.append("By model:")
            for (model, count) in sortedBreakdown(stats.modelBreakdown) {
                lines.append("  \(model): \(count)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func sortedBreakdown(_ breakdown: [String: Int]) -> [(key: String, value: Int)] {
        breakdown.sorted { $0.value > $1.value }
    }

    private static func formatPercent(_ value: Double) -> String {
        if value == 0 { return "0%" }
        if value == 1 { return "100%" }
        return String(format: "%.1f%%", value * 100)
    }
}
