import Foundation

enum HUDContentSupport {
    /// Determine if a HUD state is a diff overlay state.
    static func isDiffState(_ state: HUDOverlayState) -> Bool {
        if case .successWithDiff = state { return true }
        return false
    }

    /// Determine whether the spinner should be shown for a given state.
    static func showsSpinner(for state: HUDOverlayState) -> Bool {
        if case .working = state { return true }
        return false
    }

    /// Named color for the tint overlay per state.
    static func tintColorName(for state: HUDOverlayState) -> String {
        switch state {
        case .working:
            return "systemBlue"
        case .success, .successWithCount:
            return "systemGreen"
        case .successWithDiff:
            return "systemGreen"
        case .fallback:
            return "systemOrange"
        case .error:
            return "systemRed"
        }
    }

    /// Compute effective dismiss delay combining override with state-based default.
    static func effectiveDismissDelay(override: TimeInterval?, state: HUDOverlayState) -> TimeInterval? {
        if let override = override {
            return override
        }
        return HUDOverlaySupport.autoDismissDelay(for: state)
    }

    /// Filter diff segments for HUD display — keep only equal and insertion segments.
    static func filterSegmentsForHUD(_ segments: [DiffSegment]) -> [DiffSegment] {
        return segments.filter { $0.kind != .deletion }
    }
}
