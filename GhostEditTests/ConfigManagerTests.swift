import XCTest
@testable import GhostEditCore

final class ConfigManagerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for root in tempRoots {
            try? fileManager.removeItem(at: root)
        }
        tempRoots.removeAll()
        try super.tearDownWithError()
    }

    func testBootstrapCreatesDefaultFiles() throws {
        let (manager, _) = makeManager()

        try manager.bootstrapIfNeeded()

        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.baseDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.promptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.configURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.historyURL.path))

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, manager.defaultPrompt)

        let config = manager.loadConfig()
        XCTAssertEqual(config.provider, CLIProvider.default.rawValue)
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
        XCTAssertEqual(config.codexPath, AppConfig.default.codexPath)
        XCTAssertEqual(config.geminiPath, AppConfig.default.geminiPath)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
        XCTAssertEqual(config.historyLimit, AppConfig.default.historyLimit)
        XCTAssertEqual(config.developerMode, AppConfig.default.developerMode)
    }

    func testBootstrapMigratesLegacyDirectory() throws {
        let (manager, homeURL) = makeManager()
        let fileManager = FileManager.default

        let legacyDirectory = homeURL.appendingPathComponent(".grammarfixer", isDirectory: true)
        try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try "legacy prompt".write(
            to: legacyDirectory.appendingPathComponent("prompt.txt"),
            atomically: true,
            encoding: .utf8
        )

        let legacyConfig = AppConfig(
            claudePath: "/tmp/claude",
            codexPath: "/tmp/codex",
            geminiPath: "/tmp/gemini",
            provider: "gemini",
            model: "gemini-2.5-flash",
            timeoutSeconds: 42,
            hotkeyKeyCode: 11,
            hotkeyModifiers: 256,
            launchAtLogin: true,
            historyLimit: 15
        )
        let legacyData = try JSONEncoder().encode(legacyConfig)
        try legacyData.write(to: legacyDirectory.appendingPathComponent("config.json"), options: .atomic)

        try manager.bootstrapIfNeeded()

        XCTAssertFalse(fileManager.fileExists(atPath: legacyDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: manager.baseDirectoryURL.path))

        let migratedPrompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(migratedPrompt, "legacy prompt")

        let migratedConfig = manager.loadConfig()
        XCTAssertEqual(migratedConfig.claudePath, legacyConfig.claudePath)
        XCTAssertEqual(migratedConfig.codexPath, legacyConfig.codexPath)
        XCTAssertEqual(migratedConfig.geminiPath, legacyConfig.geminiPath)
        XCTAssertEqual(migratedConfig.provider, legacyConfig.provider)
        XCTAssertEqual(migratedConfig.model, legacyConfig.model)
        XCTAssertEqual(migratedConfig.timeoutSeconds, legacyConfig.timeoutSeconds)
        XCTAssertEqual(migratedConfig.hotkeyKeyCode, legacyConfig.hotkeyKeyCode)
        XCTAssertEqual(migratedConfig.hotkeyModifiers, legacyConfig.hotkeyModifiers)
        XCTAssertEqual(migratedConfig.launchAtLogin, legacyConfig.launchAtLogin)
        XCTAssertEqual(migratedConfig.historyLimit, legacyConfig.historyLimit)
        XCTAssertEqual(migratedConfig.developerMode, legacyConfig.developerMode)
    }

    func testBootstrapPreservesExistingFiles() throws {
        let (manager, _) = makeManager()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.baseDirectoryURL, withIntermediateDirectories: true)

        try "custom prompt".write(to: manager.promptURL, atomically: true, encoding: .utf8)
        let customConfig = AppConfig(
            claudePath: "/bin/claude",
            codexPath: "/bin/codex",
            geminiPath: "/bin/gemini",
            provider: "codex",
            model: "",
            timeoutSeconds: 60,
            hotkeyKeyCode: 7,
            hotkeyModifiers: 512,
            launchAtLogin: true,
            historyLimit: 50
        )
        try JSONEncoder().encode(customConfig).write(to: manager.configURL, options: .atomic)

        try manager.bootstrapIfNeeded()

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, "custom prompt")

        let loaded = manager.loadConfig()
        XCTAssertEqual(loaded.claudePath, customConfig.claudePath)
        XCTAssertEqual(loaded.codexPath, customConfig.codexPath)
        XCTAssertEqual(loaded.geminiPath, customConfig.geminiPath)
        XCTAssertEqual(loaded.provider, customConfig.provider)
        XCTAssertEqual(loaded.model, AppConfig.defaultModel(for: .codex))
        XCTAssertEqual(loaded.timeoutSeconds, customConfig.timeoutSeconds)
        XCTAssertEqual(loaded.hotkeyKeyCode, customConfig.hotkeyKeyCode)
        XCTAssertEqual(loaded.hotkeyModifiers, customConfig.hotkeyModifiers)
        XCTAssertEqual(loaded.launchAtLogin, customConfig.launchAtLogin)
        XCTAssertEqual(loaded.historyLimit, customConfig.historyLimit)
        XCTAssertEqual(loaded.developerMode, customConfig.developerMode)
    }

    func testBootstrapMigratesLegacyDefaultPromptToCurrentDefault() throws {
        let (manager, _) = makeManager()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.baseDirectoryURL, withIntermediateDirectories: true)

        let legacyPrompt = "Fix the grammar, spelling, and punctuation of the following text. Improve clarity and flow, but keep the tone authentic. Return ONLY the fixed text. Do not add introductory conversational filler."
        try legacyPrompt.write(to: manager.promptURL, atomically: true, encoding: .utf8)

        try manager.bootstrapIfNeeded()

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, manager.defaultPrompt)
    }

    func testBootstrapMigratesV11DefaultPromptToCurrentDefault() throws {
        let (manager, _) = makeManager()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.baseDirectoryURL, withIntermediateDirectories: true)

        let v11Prompt = "Edit the following text for grammar, spelling, and punctuation. Improve clarity and flow while preserving the original meaning, message sequence, and authentic tone. Keep the final writing absolutely professional, concise, and direct. Where natural, reflect these behaviors in tone: think big, deliver user value fast, own it, raise the bar, dive deep, learn and grow, and support each other. Return ONLY the revised text with no introductory or conversational filler."
        try v11Prompt.write(to: manager.promptURL, atomically: true, encoding: .utf8)

        try manager.bootstrapIfNeeded()

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, manager.defaultPrompt)
    }

    func testLoadPromptFallsBackWhenPromptIsWhitespace() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "\n  \t\n".write(to: manager.promptURL, atomically: true, encoding: .utf8)

        let prompt = try manager.loadPrompt()
        XCTAssertEqual(prompt, manager.defaultPrompt)
    }

    func testLoadPromptReturnsTrimmedPromptWhenNonEmpty() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "\n  Keep this prompt.   \n".write(to: manager.promptURL, atomically: true, encoding: .utf8)

        let prompt = try manager.loadPrompt()
        XCTAssertEqual(prompt, "Keep this prompt.")
    }

    func testLoadConfigReturnsDefaultWhenConfigIsInvalid() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "{ this is not valid json }".write(to: manager.configURL, atomically: true, encoding: .utf8)

        let config = manager.loadConfig()
        XCTAssertEqual(config.provider, AppConfig.default.provider)
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
        XCTAssertEqual(config.codexPath, AppConfig.default.codexPath)
        XCTAssertEqual(config.geminiPath, AppConfig.default.geminiPath)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
        XCTAssertEqual(config.historyLimit, AppConfig.default.historyLimit)
        XCTAssertEqual(config.developerMode, AppConfig.default.developerMode)
    }

    func testLoadConfigAppliesDecoderDefaultsForMissingFields() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "{\"timeoutSeconds\": 12}".write(to: manager.configURL, atomically: true, encoding: .utf8)

        let config = manager.loadConfig()
        XCTAssertEqual(config.timeoutSeconds, 12)
        XCTAssertEqual(config.provider, AppConfig.default.provider)
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
        XCTAssertEqual(config.codexPath, AppConfig.default.codexPath)
        XCTAssertEqual(config.geminiPath, AppConfig.default.geminiPath)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
        XCTAssertEqual(config.historyLimit, AppConfig.default.historyLimit)
        XCTAssertEqual(config.developerMode, AppConfig.default.developerMode)
    }

    func testLoadConfigUsesDefaultTimeoutWhenTimeoutMissing() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "{\"model\": \"sonnet\"}".write(to: manager.configURL, atomically: true, encoding: .utf8)

        let config = manager.loadConfig()
        XCTAssertEqual(config.model, "sonnet")
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
    }

    func testSaveConfigNormalizesTimeoutProviderAndModel() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        let raw = AppConfig(
            claudePath: " /opt/homebrew/bin/claude ",
            codexPath: " /opt/homebrew/bin/codex ",
            geminiPath: " /opt/homebrew/bin/gemini ",
            provider: "invalid-provider",
            model: "   ",
            timeoutSeconds: 1,
            hotkeyKeyCode: 33,
            hotkeyModifiers: 512,
            launchAtLogin: true,
            historyLimit: 0
        )

        try manager.saveConfig(raw)
        let loaded = manager.loadConfig()

        XCTAssertEqual(loaded.claudePath, raw.claudePath)
        XCTAssertEqual(loaded.codexPath, raw.codexPath)
        XCTAssertEqual(loaded.geminiPath, raw.geminiPath)
        XCTAssertEqual(loaded.provider, CLIProvider.default.rawValue)
        XCTAssertEqual(loaded.model, AppConfig.defaultModel(for: .claude))
        XCTAssertEqual(loaded.timeoutSeconds, 5)
        XCTAssertEqual(loaded.hotkeyKeyCode, raw.hotkeyKeyCode)
        XCTAssertEqual(loaded.hotkeyModifiers, raw.hotkeyModifiers)
        XCTAssertEqual(loaded.launchAtLogin, true)
        XCTAssertEqual(loaded.historyLimit, 1)
    }

    func testAppConfigResolvedPropertiesForProviderPathModelAndFallbacks() {
        let config = AppConfig(
            claudePath: "  /usr/local/bin/claude  ",
            codexPath: "  /usr/local/bin/codex  ",
            geminiPath: "  /usr/local/bin/gemini  ",
            provider: " GeMiNi ",
            model: "   ",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 20
        )

        XCTAssertEqual(config.resolvedClaudePath, "/usr/local/bin/claude")
        XCTAssertEqual(config.resolvedCodexPath, "/usr/local/bin/codex")
        XCTAssertEqual(config.resolvedGeminiPath, "/usr/local/bin/gemini")
        XCTAssertEqual(config.resolvedProvider, .gemini)
        XCTAssertEqual(config.resolvedModel(for: .claude), "haiku")
        XCTAssertEqual(config.resolvedModel(for: .codex), "gpt-5-codex")
        XCTAssertEqual(config.resolvedModel(for: .gemini), "gemini-2.5-flash-lite")
    }

    func testAppConfigResolvedModelUsesResolvedProviderWhenArgumentIsNil() {
        let codexConfig = AppConfig(
            claudePath: "",
            codexPath: "",
            geminiPath: "",
            provider: "codex",
            model: "   ",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 20
        )
        XCTAssertEqual(codexConfig.resolvedModel(), "gpt-5-codex")

        let fallbackConfig = AppConfig(
            claudePath: "",
            codexPath: "",
            geminiPath: "",
            provider: "unknown",
            model: "   ",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 20
        )
        XCTAssertEqual(fallbackConfig.resolvedModel(), "haiku")
    }

    func testAppConfigResolvedProviderFallsBackToDefaultWhenInvalid() {
        let config = AppConfig(
            claudePath: "",
            codexPath: "",
            geminiPath: "",
            provider: "???",
            model: "haiku",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 20
        )

        XCTAssertEqual(config.resolvedProvider, .claude)
    }

    func testAppConfigResolvedClaudePathReturnsNilWhenBlank() {
        let config = AppConfig(
            claudePath: " \n\t ",
            codexPath: "",
            geminiPath: "",
            provider: "claude",
            model: "haiku",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 20
        )

        XCTAssertNil(config.resolvedClaudePath)
    }

    func testCLIProviderMetadata() {
        XCTAssertEqual(CLIProvider.claude.displayName, "Claude")
        XCTAssertEqual(CLIProvider.codex.displayName, "Codex")
        XCTAssertEqual(CLIProvider.gemini.displayName, "Gemini")

        XCTAssertEqual(CLIProvider.claude.executableName, "claude")
        XCTAssertEqual(CLIProvider.codex.executableName, "codex")
        XCTAssertEqual(CLIProvider.gemini.executableName, "gemini")

        XCTAssertEqual(CLIProvider.claude.authCommand, "claude auth login")
        XCTAssertEqual(CLIProvider.codex.authCommand, "codex login")
        XCTAssertEqual(CLIProvider.gemini.authCommand, "gemini")

        XCTAssertEqual(CLIProvider.claude.configPathKey, "claudePath")
        XCTAssertEqual(CLIProvider.codex.configPathKey, "codexPath")
        XCTAssertEqual(CLIProvider.gemini.configPathKey, "geminiPath")

        XCTAssertEqual(CLIProvider.claude.defaultModel, "haiku")
        XCTAssertEqual(CLIProvider.codex.defaultModel, "gpt-5-codex")
        XCTAssertEqual(CLIProvider.gemini.defaultModel, "gemini-2.5-flash-lite")

        XCTAssertEqual(CLIProvider.claude.availableModels, ["haiku", "sonnet", "opus"])
        XCTAssertEqual(CLIProvider.codex.availableModels, ["gpt-5-codex", "gpt-5.3-codex", "gpt-5"])
        XCTAssertEqual(CLIProvider.gemini.availableModels, [
            "gemini-2.5-flash-lite",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-3-flash-preview",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3.1-pro-preview-customtools"
        ])
    }

    func testLoadConfigReturnsCachedValueWithoutRereadingDisk() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        let first = manager.loadConfig()
        XCTAssertEqual(first.model, AppConfig.default.model)

        // Overwrite the config file on disk with a different model.
        let altered = AppConfig(
            claudePath: "",
            codexPath: "",
            geminiPath: "",
            provider: "claude",
            model: "opus",
            timeoutSeconds: 60,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 200
        )
        try JSONEncoder().encode(altered).write(to: manager.configURL, options: .atomic)

        // Second call should return the cached value, not the disk value.
        let second = manager.loadConfig()
        XCTAssertEqual(second.model, first.model)
    }

    func testLoadPromptReturnsCachedValueWithoutRereadingDisk() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        let first = try manager.loadPrompt()
        XCTAssertEqual(first, manager.defaultPrompt)

        // Overwrite the prompt file on disk.
        try "completely different prompt".write(to: manager.promptURL, atomically: true, encoding: .utf8)

        // Second call should return the cached value.
        let second = try manager.loadPrompt()
        XCTAssertEqual(second, first)
    }

    func testSaveConfigInvalidatesBothCaches() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        // Populate both caches.
        _ = manager.loadConfig()
        _ = try manager.loadPrompt()

        // Save a new config (this should invalidate caches).
        var config = manager.loadConfig()
        config.model = "sonnet"
        try manager.saveConfig(config)

        // Overwrite prompt on disk after save.
        try "fresh prompt after save".write(to: manager.promptURL, atomically: true, encoding: .utf8)

        // loadConfig should re-read and get the saved value.
        let reloaded = manager.loadConfig()
        XCTAssertEqual(reloaded.model, "sonnet")

        // loadPrompt should re-read and get the new disk value.
        let reloadedPrompt = try manager.loadPrompt()
        XCTAssertEqual(reloadedPrompt, "fresh prompt after save")
    }

    func testInvalidateCacheClearsBothCaches() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        // Populate both caches.
        _ = manager.loadConfig()
        _ = try manager.loadPrompt()

        // Change files on disk.
        let altered = AppConfig(
            claudePath: "",
            codexPath: "",
            geminiPath: "",
            provider: "claude",
            model: "opus",
            timeoutSeconds: 60,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256,
            launchAtLogin: false,
            historyLimit: 200
        )
        try JSONEncoder().encode(altered).write(to: manager.configURL, options: .atomic)
        try "invalidated prompt".write(to: manager.promptURL, atomically: true, encoding: .utf8)

        // Invalidate caches.
        manager.invalidateCache()

        // Now reads should reflect the on-disk changes.
        let config = manager.loadConfig()
        XCTAssertEqual(config.model, "opus")

        let prompt = try manager.loadPrompt()
        XCTAssertEqual(prompt, "invalidated prompt")
    }

    func testDefaultInitializerUsesCurrentUserHomeDirectory() {
        let manager = ConfigManager()
        let expectedBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghostedit", isDirectory: true)
            .path
        XCTAssertEqual(manager.baseDirectoryURL.path, expectedBase)
        XCTAssertEqual(
            manager.historyURL.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ghostedit", isDirectory: true)
                .appendingPathComponent("history.json")
                .path
        )
    }

    func testLanguageDefaultIsAuto() {
        XCTAssertEqual(AppConfig.default.language, "auto")
        XCTAssertEqual(AppConfig.default.resolvedLanguage, "auto")
    }

    func testResolvedLanguageNormalizesBlankToAuto() {
        var config = AppConfig.default
        config.language = "   "
        XCTAssertEqual(config.resolvedLanguage, "auto")
    }

    func testResolvedLanguageLowercases() {
        var config = AppConfig.default
        config.language = " FR "
        XCTAssertEqual(config.resolvedLanguage, "fr")
    }

    func testLanguageInstructionForAuto() {
        let instruction = AppConfig.languageInstruction(for: "auto")
        XCTAssertEqual(instruction, "Detect the language of the input text and respond in the same language.")
    }

    func testLanguageInstructionForEmpty() {
        let instruction = AppConfig.languageInstruction(for: "")
        XCTAssertEqual(instruction, "Detect the language of the input text and respond in the same language.")
    }

    func testLanguageInstructionForKnownLanguage() {
        XCTAssertEqual(AppConfig.languageInstruction(for: "fr"), "Respond in French.")
        XCTAssertEqual(AppConfig.languageInstruction(for: "ja"), "Respond in Japanese.")
        XCTAssertEqual(AppConfig.languageInstruction(for: "ta"), "Respond in Tamil.")
    }

    func testLanguageInstructionForUnknownLanguageUsesRawValue() {
        XCTAssertEqual(AppConfig.languageInstruction(for: "klingon"), "Respond in klingon.")
    }

    func testLanguageRoundTripsViaConfigManager() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertEqual(config.resolvedLanguage, "auto")

        config.language = "es"
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertEqual(manager.loadConfig().resolvedLanguage, "es")
    }

    func testLanguageDecodesFromJSON() throws {
        let json = """
        {"language": "de", "provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.resolvedLanguage, "de")
    }

    func testLanguageDefaultsWhenMissingFromJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.resolvedLanguage, "auto")
    }

    func testSupportedLanguagesContainsAutoAndEnglish() {
        let codes = AppConfig.supportedLanguages.map { $0.code }
        XCTAssertTrue(codes.contains("auto"))
        XCTAssertTrue(codes.contains("en"))
        XCTAssertGreaterThan(codes.count, 10)
    }

    // MARK: - Sound Feedback Toggle Tests

    func testSoundFeedbackEnabledDefaultIsTrue() {
        XCTAssertTrue(AppConfig.default.soundFeedbackEnabled)
    }

    func testSoundFeedbackEnabledBackwardCompatJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.soundFeedbackEnabled)
    }

    func testSoundFeedbackEnabledRoundTrip() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertTrue(config.soundFeedbackEnabled)

        config.soundFeedbackEnabled = false
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertFalse(manager.loadConfig().soundFeedbackEnabled)
    }

    // MARK: - Notification Center Integration Tests

    func testNotifyOnSuccessDefaultIsFalse() {
        XCTAssertFalse(AppConfig.default.notifyOnSuccess)
    }

    func testNotifyOnSuccessBackwardCompatJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.notifyOnSuccess)
    }

    func testNotifyOnSuccessRoundTrip() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertFalse(config.notifyOnSuccess)

        config.notifyOnSuccess = true
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertTrue(manager.loadConfig().notifyOnSuccess)
    }

    // MARK: - Clipboard-Only Mode Tests

    func testClipboardOnlyModeDefaultIsFalse() {
        XCTAssertFalse(AppConfig.default.clipboardOnlyMode)
    }

    func testClipboardOnlyModeBackwardCompatJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.clipboardOnlyMode)
    }

    func testClipboardOnlyModeRoundTrip() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertFalse(config.clipboardOnlyMode)

        config.clipboardOnlyMode = true
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertTrue(manager.loadConfig().clipboardOnlyMode)
    }

    // MARK: - Tone/Style Presets Tests

    func testTonePresetDefaultIsDefault() {
        XCTAssertEqual(AppConfig.default.tonePreset, "default")
    }

    func testTonePresetBackwardCompatJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.tonePreset, "default")
    }

    func testTonePresetRoundTrip() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertEqual(config.tonePreset, "default")

        config.tonePreset = "professional"
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertEqual(manager.loadConfig().tonePreset, "professional")
    }

    func testSupportedPresetsContainsExpectedValues() {
        let presets = AppConfig.supportedPresets
        XCTAssertEqual(presets, ["default", "casual", "professional", "academic", "slack"])
    }

    func testPromptForPresetReturnsNilForDefault() {
        XCTAssertNil(AppConfig.promptForPreset("default"))
        XCTAssertNil(AppConfig.promptForPreset(""))
    }

    func testPromptForPresetReturnsPromptForKnownPresets() {
        XCTAssertNotNil(AppConfig.promptForPreset("casual"))
        XCTAssertNotNil(AppConfig.promptForPreset("professional"))
        XCTAssertNotNil(AppConfig.promptForPreset("academic"))
        XCTAssertNotNil(AppConfig.promptForPreset("slack"))
    }

    func testPromptForPresetReturnsNilForUnknown() {
        XCTAssertNil(AppConfig.promptForPreset("unknown-preset"))
    }

    func testPromptForPresetIsCaseInsensitive() {
        XCTAssertNotNil(AppConfig.promptForPreset("CASUAL"))
        XCTAssertNotNil(AppConfig.promptForPreset(" Professional "))
    }

    func testTonePresetNormalizesToDefaultForInvalidValue() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        config.tonePreset = "invalid-tone"
        try manager.saveConfig(config)
        manager.invalidateCache()
        XCTAssertEqual(manager.loadConfig().tonePreset, "default")
    }

    private func makeManager() -> (ConfigManager, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-tests-\(UUID().uuidString)", isDirectory: true)
        tempRoots.append(root)
        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: root)
        return (manager, root)
    }
}
