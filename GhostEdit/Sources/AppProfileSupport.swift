import Foundation

struct AppProfile: Codable, Equatable {
    var bundleIdentifier: String
    var tonePreset: String?
    var model: String?
    var provider: String?
}

enum AppProfileSupport {
    /// Resolve the effective config for a given app bundle identifier.
    /// If a matching profile exists, override matching fields in the config.
    static func resolvedConfig(
        base: AppConfig,
        profiles: [AppProfile],
        bundleIdentifier: String?
    ) -> AppConfig {
        guard let bundleID = bundleIdentifier,
              let profile = profiles.first(where: { $0.bundleIdentifier == bundleID })
        else {
            return base
        }
        return apply(profile: profile, to: base)
    }

    /// Apply a profile's overrides to a base config.
    static func apply(profile: AppProfile, to config: AppConfig) -> AppConfig {
        var result = config
        if let tone = profile.tonePreset, !tone.isEmpty {
            result.tonePreset = tone
        }
        if let model = profile.model, !model.isEmpty {
            result.model = model
        }
        if let provider = profile.provider, !provider.isEmpty {
            result.provider = provider
        }
        return result
    }

    /// Load app profiles from a JSON file in the config directory.
    static func loadProfiles(from url: URL) -> [AppProfile] {
        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([AppProfile].self, from: data)
        else {
            return []
        }
        return profiles
    }

    /// Save app profiles to a JSON file.
    static func saveProfiles(_ profiles: [AppProfile], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: url, options: .atomic)
    }
}
