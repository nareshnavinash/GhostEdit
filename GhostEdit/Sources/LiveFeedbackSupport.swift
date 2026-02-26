import CoreGraphics
import Foundation

enum LiveFeedbackState: Equatable {
    case idle
    case checking
    case clean
    case issues(Int)
    case unavailable(String)
}

enum LiveFeedbackSupport {
    // MARK: - Widget Layout

    static let widgetWidth: CGFloat = 180
    static let widgetHeight: CGFloat = 28
    static let widgetCornerRadius: CGFloat = 8
    static let widgetFontSize: CGFloat = 12
    static let widgetPadding: CGFloat = 8
    static let widgetOffsetY: CGFloat = 4

    // MARK: - Popover Layout

    static let popoverWidth: CGFloat = 280
    static let popoverRowHeight: CGFloat = 44
    static let popoverMaxVisibleRows: Int = 6
    static let popoverCornerRadius: CGFloat = 10
    static let popoverPadding: CGFloat = 8

    // MARK: - Timing

    static let pollingInterval: TimeInterval = 1.5
    static let widgetFadeInDuration: CGFloat = 0.2
    static let widgetFadeOutDuration: CGFloat = 0.15
    static let cleanAutoDismissDelay: TimeInterval = 3.0
    static let issuePopoverAutoDismissDelay: TimeInterval = 5.0

    // MARK: - State Display

    /// Returns the display text for the live feedback widget.
    static func statusText(for state: LiveFeedbackState) -> String {
        switch state {
        case .idle:
            return "Live Check"
        case .checking:
            return "Checking\u{2026}"
        case .clean:
            return "All clear"
        case .issues(let count):
            return count == 1 ? "1 issue found" : "\(count) issues found"
        case .unavailable(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Unavailable" : trimmed
        }
    }

    /// Returns a named color identifier for the status dot.
    static func statusColorName(for state: LiveFeedbackState) -> String {
        switch state {
        case .idle:
            return "systemGray"
        case .checking:
            return "systemOrange"
        case .clean:
            return "systemGreen"
        case .issues:
            return "systemRed"
        case .unavailable:
            return "systemGray"
        }
    }

    /// Returns whether the widget should auto-dismiss for this state.
    static func autoDismissDelay(for state: LiveFeedbackState) -> TimeInterval? {
        switch state {
        case .clean:
            return cleanAutoDismissDelay
        case .idle, .checking, .issues, .unavailable:
            return nil
        }
    }

    /// Returns the maximum popover height based on issue count.
    static func popoverHeight(for issueCount: Int) -> CGFloat {
        let visibleRows = min(issueCount, popoverMaxVisibleRows)
        let contentHeight = CGFloat(max(visibleRows, 1)) * popoverRowHeight
        return contentHeight + popoverPadding * 2
    }
}
