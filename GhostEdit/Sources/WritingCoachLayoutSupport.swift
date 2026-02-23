import CoreGraphics

enum WritingCoachLayoutSupport {
    static let accessoryWidth: CGFloat = 560
    static let panelSpacing: CGFloat = 16
    static let panelInset: CGFloat = 16
    static let cornerRadius: CGFloat = 10
    static let borderAlpha: CGFloat = 0.4
    static let backgroundAlpha: CGFloat = 0.05
    static let headerFontSize: CGFloat = 14
    static let itemFontSize: CGFloat = 13

    static let strengthPrefix = "✓ "
    static let improvementPrefix = "→ "

    static let emptyStrengthsFallback = "No recurring strengths detected yet."
    static let emptyImprovementsFallback = "No specific improvements suggested yet."

    static func cappedItems(_ items: [String], limit: Int = 5) -> [String] {
        Array(items.prefix(max(0, limit)))
    }

    static func panelContentWidth() -> CGFloat {
        let panelWidth = (accessoryWidth - panelSpacing) / 2.0
        return panelWidth - (panelInset * 2)
    }

    static func reviewedText(sampleCount: Int) -> String {
        "Reviewed \(sampleCount) writing sample(s)."
    }
}
