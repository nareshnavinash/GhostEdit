import CoreGraphics

enum SettingsLayoutSupport {
    static let windowWidth: CGFloat = 560
    static let minWindowHeight: CGFloat = 520
    static let verticalInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    static let labelWidth: CGFloat = 90
    static let groupInset: CGFloat = 12
    static let groupCornerRadius: CGFloat = 8

    static func preferredWindowHeight(for contentHeight: CGFloat) -> CGFloat {
        max(minWindowHeight, ceil(contentHeight + (verticalInset * 2)))
    }
}
