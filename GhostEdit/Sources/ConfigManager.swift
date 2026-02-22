import Foundation

struct AppConfig: Codable {
    var claudePath: String
    var model: String
    var timeoutSeconds: Int
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32

    static let `default` = AppConfig(
        claudePath: "",
        model: "haiku",
        timeoutSeconds: 30,
        hotkeyKeyCode: 14,
        hotkeyModifiers: 256
    )

    enum CodingKeys: String, CodingKey {
        case claudePath
        case model
        case timeoutSeconds
        case hotkeyKeyCode
        case hotkeyModifiers
    }

    init(
        claudePath: String,
        model: String,
        timeoutSeconds: Int,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32
    ) {
        self.claudePath = claudePath
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        claudePath = try container.decodeIfPresent(String.self, forKey: .claudePath) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AppConfig.default.model
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? AppConfig.default.timeoutSeconds
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? AppConfig.default.hotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? AppConfig.default.hotkeyModifiers
    }

    var resolvedClaudePath: String? {
        let trimmed = claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppConfig.default.model : trimmed
    }
}

final class ConfigManager {
    private let fileManager: FileManager

    let baseDirectoryURL: URL
    let legacyDirectoryURL: URL
    let promptURL: URL
    let configURL: URL

    let defaultPrompt = "Edit the following text for grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, message sequence, and authentic tone. Keep the final writing absolutely professional, concise, and direct. Where natural, reflect these behaviors in tone: think big, deliver user value fast, own it, raise the bar, dive deep, learn and grow, and support each other. Return ONLY the revised text with no introductory or conversational filler."
    private let legacyDefaultPrompts: Set<String> = [
        "Fix the grammar, spelling, and punctuation of the following text. Improve clarity and flow, but keep the tone authentic. Return ONLY the fixed text. Do not add introductory conversational filler."
    ]

    init(fileManager: FileManager = .default, homeDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        let homeURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        baseDirectoryURL = homeURL
            .appendingPathComponent(".ghostedit", isDirectory: true)
        legacyDirectoryURL = homeURL
            .appendingPathComponent(".grammarfixer", isDirectory: true)
        promptURL = baseDirectoryURL.appendingPathComponent("prompt.txt")
        configURL = baseDirectoryURL.appendingPathComponent("config.json")
    }

    func bootstrapIfNeeded() throws {
        try migrateLegacyDirectoryIfNeeded()

        if !fileManager.fileExists(atPath: baseDirectoryURL.path) {
            try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: promptURL.path) {
            try defaultPrompt.write(to: promptURL, atomically: true, encoding: .utf8)
        }
        try migratePromptIfNeeded()

        if !fileManager.fileExists(atPath: configURL.path) {
            let data = try JSONEncoder.prettyEncoder.encode(AppConfig.default)
            try data.write(to: configURL)
        }
    }

    func loadPrompt() throws -> String {
        let prompt = try String(contentsOf: promptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return prompt.isEmpty ? defaultPrompt : prompt
    }

    func loadConfig() -> AppConfig {
        guard
            let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig.default
        }

        return normalize(decoded)
    }

    func saveConfig(_ config: AppConfig) throws {
        let normalized = normalize(config)
        let data = try JSONEncoder.prettyEncoder.encode(normalized)
        try data.write(to: configURL, options: .atomic)
    }

    private func normalize(_ config: AppConfig) -> AppConfig {
        let timeout = max(5, config.timeoutSeconds)
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppConfig(
            claudePath: config.claudePath,
            model: model.isEmpty ? AppConfig.default.model : model,
            timeoutSeconds: timeout,
            hotkeyKeyCode: config.hotkeyKeyCode,
            hotkeyModifiers: config.hotkeyModifiers
        )
    }

    private func migratePromptIfNeeded() throws {
        let existingPrompt = try String(contentsOf: promptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard legacyDefaultPrompts.contains(existingPrompt) else {
            return
        }

        try defaultPrompt.write(to: promptURL, atomically: true, encoding: .utf8)
    }

    private func migrateLegacyDirectoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path) else {
            return
        }

        guard fileManager.fileExists(atPath: legacyDirectoryURL.path) else {
            return
        }

        try fileManager.moveItem(at: legacyDirectoryURL, to: baseDirectoryURL)
    }
}

private extension JSONEncoder {
    static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
