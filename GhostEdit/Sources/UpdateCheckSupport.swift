import Foundation

struct VersionInfo: Equatable {
    let current: String
    let latest: String
    let isUpdateAvailable: Bool
    let releaseURL: String?
}

enum UpdateCheckSupport {
    static let defaultReleaseURL = "https://github.com/nareshnavinash/GhostEdit/releases/latest"

    /// Compare two semantic version strings. Returns `true` if `latest` is
    /// newer than `current`.
    static func isNewer(current: String, latest: String) -> Bool {
        let currentParts = parseSemver(current)
        let latestParts = parseSemver(latest)

        for i in 0..<max(currentParts.count, latestParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    /// Parse a semver string like "4.2.0" or "v4.2.0-beta.1" into numeric parts.
    static func parseSemver(_ version: String) -> [Int] {
        let cleaned = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "v", with: "")
        let parts = cleaned.components(separatedBy: "-")
        let base = parts.isEmpty ? cleaned : parts[0]
        return base
            .components(separatedBy: ".")
            .compactMap { Int($0) }
    }

    /// Build a VersionInfo from current and latest version strings.
    static func checkVersion(current: String, latest: String) -> VersionInfo {
        VersionInfo(
            current: current,
            latest: latest,
            isUpdateAvailable: isNewer(current: current, latest: latest),
            releaseURL: defaultReleaseURL
        )
    }
}
