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
            return [
                "claude-haiku-4-5",
                "claude-sonnet-4-5",
                "claude-sonnet-4-6",
                "claude-opus-4-6",
                "haiku",
                "sonnet",
                "opus"
            ]
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
            return "claude-haiku-4-5"
        case .codex:
            return "gpt-5-codex"
        case .gemini:
            return "gemini-2.5-flash-lite"
        }
    }
}

struct AppConfig: Codable, Equatable {
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
    var developerMode: Bool
    var language: String
    var soundFeedbackEnabled: Bool
    var notifyOnSuccess: Bool
    var clipboardOnlyMode: Bool
    var tonePreset: String
    var showDiffPreview: Bool
    var liveFeedbackEnabled: Bool
    var diffPreviewDuration: Int
    var localModelRepoID: String
    var localModelCustomModels: String
    var localModelPythonPath: String

    static let `default` = AppConfig(
        claudePath: "",
        codexPath: "",
        geminiPath: "",
        provider: CLIProvider.default.rawValue,
        model: "sonnet",
        timeoutSeconds: 60,
        hotkeyKeyCode: 14,
        hotkeyModifiers: 256,
        launchAtLogin: false,
        historyLimit: 50,
        developerMode: false,
        language: "auto",
        soundFeedbackEnabled: true,
        notifyOnSuccess: false,
        clipboardOnlyMode: false,
        tonePreset: "default",
        showDiffPreview: false,
        liveFeedbackEnabled: false,
        diffPreviewDuration: 3,
        localModelRepoID: "",
        localModelCustomModels: "[]",
        localModelPythonPath: ""
    )

    static let supportedPresets: [String] = [
        "default", "casual", "professional", "academic", "slack"
    ]

    static func promptForPreset(_ preset: String) -> String? {
        switch preset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default", "":
            return nil
        case "casual":
            return "Revise the following text for grammar and spelling. Use a casual, friendly, and conversational tone. Keep it natural and relaxed. Preserve all line breaks, blank lines, and paragraph spacing exactly as in the original. Return ONLY the revised text."
        case "professional":
            return "Revise the following text for grammar, spelling, and punctuation. Use a polished, professional tone suitable for business communication. Be concise and direct. Preserve all line breaks, blank lines, and paragraph spacing exactly as in the original. Return ONLY the revised text."
        case "academic":
            return "Revise the following text for grammar, spelling, and punctuation. Use a formal academic tone with precise language. Maintain objectivity and clarity. Preserve all line breaks, blank lines, and paragraph spacing exactly as in the original. Return ONLY the revised text."
        case "slack":
            return "Revise the following text for grammar and spelling. Keep a concise, upbeat Slack-message tone. Use short sentences. Preserve all line breaks, blank lines, and paragraph spacing exactly as in the original. Return ONLY the revised text."
        default:
            return nil
        }
    }

    static let supportedLanguages: [(code: String, displayName: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("ta", "Tamil"),
        ("ru", "Russian"),
        ("pl", "Polish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish"),
        ("tr", "Turkish"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
        ("id", "Indonesian"),
        ("ms", "Malay"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("el", "Greek"),
        ("he", "Hebrew")
    ]

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
        case developerMode
        case language
        case soundFeedbackEnabled
        case notifyOnSuccess
        case clipboardOnlyMode
        case tonePreset
        case showDiffPreview
        case liveFeedbackEnabled
        case diffPreviewDuration
        case localModelRepoID
        case localModelCustomModels
        case localModelPythonPath
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
        historyLimit: Int,
        developerMode: Bool = false,
        language: String = "auto",
        soundFeedbackEnabled: Bool = true,
        notifyOnSuccess: Bool = false,
        clipboardOnlyMode: Bool = false,
        tonePreset: String = "default",
        showDiffPreview: Bool = false,
        liveFeedbackEnabled: Bool = false,
        diffPreviewDuration: Int = 3,
        localModelRepoID: String = "",
        localModelCustomModels: String = "[]",
        localModelPythonPath: String = ""
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
        self.developerMode = developerMode
        self.language = language
        self.soundFeedbackEnabled = soundFeedbackEnabled
        self.notifyOnSuccess = notifyOnSuccess
        self.clipboardOnlyMode = clipboardOnlyMode
        self.tonePreset = tonePreset
        self.showDiffPreview = showDiffPreview
        self.liveFeedbackEnabled = liveFeedbackEnabled
        self.diffPreviewDuration = diffPreviewDuration
        self.localModelRepoID = localModelRepoID
        self.localModelCustomModels = localModelCustomModels
        self.localModelPythonPath = localModelPythonPath
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
        developerMode = try container.decodeIfPresent(Bool.self, forKey: .developerMode) ?? AppConfig.default.developerMode
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? AppConfig.default.language
        soundFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundFeedbackEnabled) ?? AppConfig.default.soundFeedbackEnabled
        notifyOnSuccess = try container.decodeIfPresent(Bool.self, forKey: .notifyOnSuccess) ?? AppConfig.default.notifyOnSuccess
        clipboardOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .clipboardOnlyMode) ?? AppConfig.default.clipboardOnlyMode
        tonePreset = try container.decodeIfPresent(String.self, forKey: .tonePreset) ?? AppConfig.default.tonePreset
        showDiffPreview = try container.decodeIfPresent(Bool.self, forKey: .showDiffPreview) ?? AppConfig.default.showDiffPreview
        liveFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveFeedbackEnabled) ?? AppConfig.default.liveFeedbackEnabled
        diffPreviewDuration = try container.decodeIfPresent(Int.self, forKey: .diffPreviewDuration) ?? AppConfig.default.diffPreviewDuration
        localModelRepoID = try container.decodeIfPresent(String.self, forKey: .localModelRepoID) ?? AppConfig.default.localModelRepoID
        localModelCustomModels = try container.decodeIfPresent(String.self, forKey: .localModelCustomModels) ?? AppConfig.default.localModelCustomModels
        localModelPythonPath = try container.decodeIfPresent(String.self, forKey: .localModelPythonPath) ?? AppConfig.default.localModelPythonPath
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

    var resolvedLanguage: String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "auto" : trimmed
    }

    static func languageInstruction(for language: String) -> String? {
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code.isEmpty || code == "auto" {
            return "Detect the language of the input text and respond in the same language."
        }
        guard let entry = supportedLanguages.first(where: { $0.code == code }) else {
            return "Respond in \(language)."
        }
        return "Respond in \(entry.displayName)."
    }
}

final class ConfigManager {
    private let fileManager: FileManager
    private var cachedConfig: AppConfig?
    private var cachedPrompt: String?

    let baseDirectoryURL: URL
    let legacyDirectoryURL: URL
    let promptURL: URL
    let configURL: URL
    let historyURL: URL
    let profilesURL: URL

    let defaultPrompt = "Please revise the following text by correcting grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, intent, and message flow. Keep the tone natural to the writer. Do not change the point of view. Preserve all line breaks, blank lines, and paragraph spacing exactly as in the original. Return ONLY the revised text, with no preface or extra commentary."
    private let legacyDefaultPrompts: Set<String> = [
        "Fix the grammar, spelling, and punctuation of the following text. Improve clarity and flow, but keep the tone authentic. Return ONLY the fixed text. Do not add introductory conversational filler.",
        "Edit the following text for grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, message sequence, and authentic tone. Keep the final writing absolutely professional, concise, and direct. Where natural, reflect these behaviors in tone: think big, deliver user value fast, own it, raise the bar, dive deep, learn and grow, and support each other. Return ONLY the revised text with no introductory or conversational filler.",
        "Please revise the following text by correcting grammar, spelling, and punctuation. Use polite, professional periphrasis while preserving the original meaning, intent, and message flow. Keep the tone natural to the writer. Return ONLY the revised text, with no preface or extra commentary.",
        "Please revise the following text by correcting grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, intent, and message flow. Keep the tone natural to the writer. Do not change the point of view. Return ONLY the revised text, with no preface or extra commentary."
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
        profilesURL = baseDirectoryURL.appendingPathComponent("profiles.json")
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

        // Ensure scripts directory exists for local model inference
        let scriptsDir = baseDirectoryURL.appendingPathComponent("scripts", isDirectory: true)
        if !fileManager.fileExists(atPath: scriptsDir.path) {
            try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        }
    }

    var scriptsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("scripts", isDirectory: true)
    }

    func loadPrompt() throws -> String {
        if let cached = cachedPrompt {
            return cached
        }

        let prompt = try String(contentsOf: promptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let result = prompt.isEmpty ? defaultPrompt : prompt
        cachedPrompt = result
        return result
    }

    func loadConfig() -> AppConfig {
        if let cached = cachedConfig {
            return cached
        }

        guard
            let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig.default
        }

        let result = normalize(decoded)
        cachedConfig = result
        return result
    }

    func saveConfig(_ config: AppConfig) throws {
        let normalized = normalize(config)
        let data = try JSONEncoder.prettyEncoder.encode(normalized)
        try data.write(to: configURL, options: .atomic)
        cachedConfig = nil
        cachedPrompt = nil
    }

    func invalidateCache() {
        cachedConfig = nil
        cachedPrompt = nil
    }

    private func normalize(_ config: AppConfig) -> AppConfig {
        let timeout = max(5, config.timeoutSeconds)
        let provider = config.resolvedProvider
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.isEmpty ? AppConfig.defaultModel(for: provider) : model
        let historyLimit = max(1, config.historyLimit)
        let normalizedTone = config.tonePreset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tonePreset = AppConfig.supportedPresets.contains(normalizedTone) ? normalizedTone : "default"

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
            historyLimit: historyLimit,
            developerMode: config.developerMode,
            language: config.resolvedLanguage,
            soundFeedbackEnabled: config.soundFeedbackEnabled,
            notifyOnSuccess: config.notifyOnSuccess,
            clipboardOnlyMode: config.clipboardOnlyMode,
            tonePreset: tonePreset,
            showDiffPreview: config.showDiffPreview,
            liveFeedbackEnabled: config.liveFeedbackEnabled,
            diffPreviewDuration: config.diffPreviewDuration,
            localModelRepoID: config.localModelRepoID,
            localModelCustomModels: config.localModelCustomModels,
            localModelPythonPath: config.localModelPythonPath
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
