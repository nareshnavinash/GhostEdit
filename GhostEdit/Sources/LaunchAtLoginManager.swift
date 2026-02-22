import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
