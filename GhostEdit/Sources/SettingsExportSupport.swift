import Foundation

struct ExportedSettings: Codable, Equatable {
    var config: AppConfig
    var prompt: String
    var exportedAt: Date
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case config
        case prompt
        case exportedAt
        case appVersion
    }
}

enum SettingsExportSupport {
    static func exportSettings(
        config: AppConfig,
        prompt: String,
        appVersion: String,
        now: Date = Date()
    ) throws -> Data {
        let exported = ExportedSettings(
            config: config,
            prompt: prompt,
            exportedAt: now,
            appVersion: appVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exported)
    }

    static func importSettings(from data: Data) throws -> ExportedSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportedSettings.self, from: data)
    }

    static func defaultFileName(appVersion: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "ghostedit-settings-\(dateString).json"
    }
}
