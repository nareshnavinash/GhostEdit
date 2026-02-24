import Foundation

protocol DeveloperModeLogger: AnyObject {
    func log(_ entry: DeveloperModeLogEntry)
}

struct DeveloperModeLogEntry: Equatable {
    enum Phase: String, Equatable, CaseIterable {
        case textCapture = "TEXT_CAPTURE"
        case tokenProtection = "TOKEN_PROTECTION"
        case cliResolution = "CLI_RESOLUTION"
        case cliExecution = "CLI_EXECUTION"
        case cliResponse = "CLI_RESPONSE"
        case tokenRestoration = "TOKEN_RESTORATION"
        case pasteBack = "PASTE_BACK"
    }

    let phase: Phase
    let message: String
    let timestamp: Date

    init(phase: Phase, message: String, timestamp: Date = Date()) {
        self.phase = phase
        self.message = message
        self.timestamp = timestamp
    }
}

enum DeveloperModeSupport {
    static let windowWidth: CGFloat = 700
    static let windowHeight: CGFloat = 480
    static let maxEntries = 5000

    static func formatEntry(_ entry: DeveloperModeLogEntry, formatter: DateFormatter) -> String {
        let time = formatter.string(from: entry.timestamp)
        return "[\(time)] [\(entry.phase.rawValue)] \(entry.message)"
    }

    static func formatAllEntries(_ entries: [DeveloperModeLogEntry], formatter: DateFormatter) -> String {
        entries.map { formatEntry($0, formatter: formatter) }.joined(separator: "\n")
    }

    static func phaseIcon(for phase: DeveloperModeLogEntry.Phase) -> String {
        switch phase {
        case .textCapture:
            return ">"
        case .tokenProtection:
            return "#"
        case .cliResolution:
            return "?"
        case .cliExecution:
            return "$"
        case .cliResponse:
            return "<"
        case .tokenRestoration:
            return "="
        case .pasteBack:
            return "^"
        }
    }

    static func truncate(_ text: String, maxLength: Int = 200) -> String {
        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]) + "..."
    }
}
