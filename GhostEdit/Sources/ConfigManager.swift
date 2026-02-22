import Foundation

enum CLIProvider: String, Codable, CaseIterable {
    case claude
    case codex
    case gemini

    static let `default`: CLIProvider = .claude

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini"
        }
    }

    var executableName: String { rawValue }

    var authCommand: String {
        switch self {
        case .claude:
            return "claude auth login"
        case .codex:
            return "codex login"
        case .gemini:
            return "gemini"
        }
    }

    var configPathKey: String {
        switch self {
        case .claude:
            return "claudePath"
        case .codex:
            return "codexPath"
        case .gemini:
            return "geminiPath"
        }
    }

    var availableModels: [String] {
        switch self {
        case .claude:
            return ["haiku", "sonnet", "opus"]
        case .codex:
            return ["gpt-5-codex", "gpt-5.3-codex", "gpt-5"]
        case .gemini:
            return [
                "gemini-2.5-flash-lite",
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-3-flash-preview",
                "gemini-3-pro-preview",
                "gemini-3.1-pro-preview",
                "gemini-3.1-pro-preview-customtools"
            ]
        }
    }

    var defaultModel: String {
        switch self {
        case .claude:
            return "haiku"
        case .codex:
            return "gpt-5-codex"
        case .gemini:
            return "gemini-2.5-flash-lite"
        }
    }
}

struct AppConfig: Codable {
    var claudePath: String
    var codexPath: String
    var geminiPath: String
    var provider: String
    var model: String
    var timeoutSeconds: Int
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var launchAtLogin: Bool
    var historyLimit: Int

    static let `default` = AppConfig(
        claudePath: "",
        codexPath: "",
        geminiPath: "",
        provider: CLIProvider.default.rawValue,
        model: "haiku",
        timeoutSeconds: 30,
        hotkeyKeyCode: 14,
        hotkeyModifiers: 256,
        launchAtLogin: false,
        historyLimit: 200
    )

    enum CodingKeys: String, CodingKey {
        case claudePath
        case codexPath
        case geminiPath
        case provider
        case model
        case timeoutSeconds
        case hotkeyKeyCode
        case hotkeyModifiers
        case launchAtLogin
        case historyLimit
    }

    init(
        claudePath: String,
        codexPath: String,
        geminiPath: String,
        provider: String,
        model: String,
        timeoutSeconds: Int,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        launchAtLogin: Bool,
        historyLimit: Int
    ) {
        self.claudePath = claudePath
        self.codexPath = codexPath
        self.geminiPath = geminiPath
        self.provider = provider
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.launchAtLogin = launchAtLogin
        self.historyLimit = historyLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        claudePath = try container.decodeIfPresent(String.self, forKey: .claudePath) ?? ""
        codexPath = try container.decodeIfPresent(String.self, forKey: .codexPath) ?? ""
        geminiPath = try container.decodeIfPresent(String.self, forKey: .geminiPath) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? CLIProvider.default.rawValue
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AppConfig.default.model
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? AppConfig.default.timeoutSeconds
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? AppConfig.default.hotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? AppConfig.default.hotkeyModifiers
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? AppConfig.default.launchAtLogin
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? AppConfig.default.historyLimit
    }

    var resolvedClaudePath: String? {
        resolvedPath(for: .claude)
    }

    var resolvedCodexPath: String? {
        resolvedPath(for: .codex)
    }

    var resolvedGeminiPath: String? {
        resolvedPath(for: .gemini)
    }

    var resolvedProvider: CLIProvider {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CLIProvider(rawValue: trimmed) ?? .default
    }

    func resolvedPath(for provider: CLIProvider) -> String? {
        let value: String
        switch provider {
        case .claude:
            value = claudePath
        case .codex:
            value = codexPath
        case .gemini:
            value = geminiPath
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func resolvedModel(for provider: CLIProvider? = nil) -> String {
        let selectedProvider = provider ?? resolvedProvider
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return AppConfig.defaultModel(for: selectedProvider)
    }

    static func defaultModel(for provider: CLIProvider) -> String {
        provider.defaultModel
    }
}

final class ConfigManager {
    private let fileManager: FileManager

    let baseDirectoryURL: URL
    let legacyDirectoryURL: URL
    let promptURL: URL
    let configURL: URL
    let historyURL: URL

    let defaultPrompt = "Please revise the following text by correcting grammar, spelling, and punctuation. Use polite, professional periphrasis while preserving the original meaning, intent, and message flow. Keep the tone natural to the writer. Return ONLY the revised text, with no preface or extra commentary."
    private let legacyDefaultPrompts: Set<String> = [
        "Fix the grammar, spelling, and punctuation of the following text. Improve clarity and flow, but keep the tone authentic. Return ONLY the fixed text. Do not add introductory conversational filler.",
        "Edit the following text for grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, message sequence, and authentic tone. Keep the final writing absolutely professional, concise, and direct. Where natural, reflect these behaviors in tone: think big, deliver user value fast, own it, raise the bar, dive deep, learn and grow, and support each other. Return ONLY the revised text with no introductory or conversational filler."
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
        historyURL = baseDirectoryURL.appendingPathComponent("history.json")
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

        if !fileManager.fileExists(atPath: historyURL.path) {
            try "[]\n".write(to: historyURL, atomically: true, encoding: .utf8)
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
        let provider = config.resolvedProvider
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.isEmpty ? AppConfig.defaultModel(for: provider) : model
        let historyLimit = max(1, config.historyLimit)

        return AppConfig(
            claudePath: config.claudePath,
            codexPath: config.codexPath,
            geminiPath: config.geminiPath,
            provider: provider.rawValue,
            model: normalizedModel,
            timeoutSeconds: timeout,
            hotkeyKeyCode: config.hotkeyKeyCode,
            hotkeyModifiers: config.hotkeyModifiers,
            launchAtLogin: config.launchAtLogin,
            historyLimit: historyLimit
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
