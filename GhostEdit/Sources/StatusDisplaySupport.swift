import Foundation

enum StatusDisplaySupport {
    enum StatusColor {
        case green
        case orange
        case red
    }

    /// Determine the status dot color based on the status text.
    static func statusColor(for text: String) -> StatusColor {
        if text == "Idle" || text.hasPrefix("Last correction") || text.hasPrefix("Settings saved") {
            return .green
        } else if text.contains("Processing") || text.contains("Working") || text.contains("Copying") || text.contains("Analyzing") || text.contains("Checking") || text.contains("Retrying") {
            return .orange
        } else if text.contains("failed") || text.contains("not found") || text.contains("required") || text.contains("No text") || text.contains("permission") {
            return .red
        } else {
            return .green
        }
    }
}
