import CoreGraphics
import Foundation

enum HUDOverlayState: Equatable {
    case working
    case success
    case error(String)
}

struct HUDOverlayContent: Equatable {
    let emoji: String
    let message: String
}

enum HUDOverlaySupport {
    // Layout
    static let windowWidth: CGFloat = 200
    static let windowHeight: CGFloat = 200
    static let cornerRadius: CGFloat = 18
    static let iconSize: CGFloat = 64
    static let messageFontSize: CGFloat = 14
    static let verticalSpacing: CGFloat = 12
    static let contentInset: CGFloat = 20

    // Timing
    static let fadeInDuration: CGFloat = 0.18
    static let fadeOutDuration: CGFloat = 0.25
    static let workingAutoDismissDelay: TimeInterval = 1.0
    static let successAutoDismissDelay: TimeInterval = 1.0
    static let errorAutoDismissDelay: TimeInterval = 2.5

    static let defaultErrorMessage = "Something went wrong"

    // SVG path data for the ghost icon (from Remotion source, viewBox 197 152 630 630).
    static let ghostBodyPath = "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z"
    static let ghostMouthPath = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z"
    static let ghostBridgePath = "M 498 385 Q 512 365 526 385"
    static let ghostLeftArmPath = "M 342 390 L 295 410"
    static let ghostRightArmPath = "M 682 390 L 729 410"
    static let ghostViewBoxOriginX: CGFloat = 197
    static let ghostViewBoxOriginY: CGFloat = 152
    static let ghostViewBoxSize: CGFloat = 630

    struct GhostEye: Equatable {
        let cx: CGFloat
        let cy: CGFloat
        let rx: CGFloat
        let ry: CGFloat
        let rotation: CGFloat
        let highlightCX: CGFloat
        let highlightCY: CGFloat
        let highlightR: CGFloat
        let lensR: CGFloat
    }

    static let ghostLeftEye = GhostEye(
        cx: 420, cy: 390, rx: 48, ry: 60, rotation: -8,
        highlightCX: 436, highlightCY: 370, highlightR: 13,
        lensR: 78
    )

    static let ghostRightEye = GhostEye(
        cx: 604, cy: 390, rx: 48, ry: 60, rotation: 8,
        highlightCX: 620, highlightCY: 370, highlightR: 13,
        lensR: 78
    )

    static let ghostStrokeWidth: CGFloat = 14

    static func content(for state: HUDOverlayState) -> HUDOverlayContent {
        switch state {
        case .working:
            return HUDOverlayContent(emoji: "\u{1F47B}", message: "Working on it...")
        case .success:
            return HUDOverlayContent(emoji: "\u{1F47B}", message: "Done!")
        case .error(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? defaultErrorMessage : trimmed
            return HUDOverlayContent(emoji: "\u{1F47B}", message: message)
        }
    }

    static func showsSpectacles(for state: HUDOverlayState) -> Bool {
        switch state {
        case .working:
            return true
        case .success, .error:
            return false
        }
    }

    static func autoDismissDelay(for state: HUDOverlayState) -> TimeInterval? {
        switch state {
        case .working:
            return workingAutoDismissDelay
        case .success:
            return successAutoDismissDelay
        case .error:
            return errorAutoDismissDelay
        }
    }

    static func windowOrigin(screenSize: CGSize) -> CGPoint {
        let x = (screenSize.width - windowWidth) / 2
        let y = (screenSize.height - windowHeight) / 2
        return CGPoint(x: x, y: y)
    }
}
