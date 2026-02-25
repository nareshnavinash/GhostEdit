import CoreGraphics

enum SettingsLayoutSupport {
    static let windowWidth: CGFloat = 520
    static let minWindowHeight: CGFloat = 300
    static let verticalInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 12
    static let labelWidth: CGFloat = 100
    static let groupInset: CGFloat = 0
    static let groupCornerRadius: CGFloat = 10

    static func preferredWindowHeight(for contentHeight: CGFloat) -> CGFloat {
        max(minWindowHeight, ceil(contentHeight + (verticalInset * 2)))
    }
}
