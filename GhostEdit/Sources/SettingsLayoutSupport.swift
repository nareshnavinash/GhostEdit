import CoreGraphics

enum SettingsLayoutSupport {
    static let windowWidth: CGFloat = 620
    static let minWindowHeight: CGFloat = 460
    static let verticalInset: CGFloat = 20

    static func preferredWindowHeight(for contentHeight: CGFloat) -> CGFloat {
        max(minWindowHeight, ceil(contentHeight + (verticalInset * 2)))
    }
}
