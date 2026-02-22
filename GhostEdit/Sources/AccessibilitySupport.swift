import Foundation

enum AccessibilitySupport {
    static func guidanceText(appName: String) -> String {
        """
        Enable \(appName) in System Settings > Privacy & Security > Accessibility so it can send Cmd+C and Cmd+V.

        If macOS asks again after an app update, keep \(appName) in /Applications and use builds signed with a consistent identity so accessibility approval can persist across updates.
        """
    }
}
