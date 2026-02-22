import Foundation

enum HistoryTableColumn: String, CaseIterable {
    case timestamp
    case status
    case provider
    case model
    case duration
    case original
    case generated
}

struct HistoryTableRow: Equatable {
    let timestamp: String
    let status: String
    let provider: String
    let model: String
    let duration: String
    let original: String
    let generated: String

    init(entry: CorrectionHistoryEntry, timestampFormatter: (Date) -> String) {
        timestamp = timestampFormatter(entry.timestamp)
        status = entry.succeeded ? "Succeeded" : "Failed"
        provider = entry.provider
        model = entry.model
        duration = "\(entry.durationMilliseconds) ms"
        original = entry.originalText
        generated = entry.generatedText
    }

    func value(for column: HistoryTableColumn) -> String {
        switch column {
        case .timestamp:
            return timestamp
        case .status:
            return status
        case .provider:
            return provider
        case .model:
            return model
        case .duration:
            return duration
        case .original:
            return original
        case .generated:
            return generated
        }
    }
}

enum HistoryTableModel {
    static func rows(
        from entries: [CorrectionHistoryEntry],
        timestampFormatter: (Date) -> String
    ) -> [HistoryTableRow] {
        entries.map { HistoryTableRow(entry: $0, timestampFormatter: timestampFormatter) }
    }
}
