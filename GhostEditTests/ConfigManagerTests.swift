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

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, manager.defaultPrompt)

        let config = manager.loadConfig()
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
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
            model: "sonnet",
            timeoutSeconds: 42,
            hotkeyKeyCode: 11,
            hotkeyModifiers: 256
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
        XCTAssertEqual(migratedConfig.model, legacyConfig.model)
        XCTAssertEqual(migratedConfig.timeoutSeconds, legacyConfig.timeoutSeconds)
        XCTAssertEqual(migratedConfig.hotkeyKeyCode, legacyConfig.hotkeyKeyCode)
        XCTAssertEqual(migratedConfig.hotkeyModifiers, legacyConfig.hotkeyModifiers)
    }

    func testBootstrapPreservesExistingFiles() throws {
        let (manager, _) = makeManager()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.baseDirectoryURL, withIntermediateDirectories: true)

        try "custom prompt".write(to: manager.promptURL, atomically: true, encoding: .utf8)
        let customConfig = AppConfig(
            claudePath: "/bin/claude",
            model: "opus",
            timeoutSeconds: 60,
            hotkeyKeyCode: 7,
            hotkeyModifiers: 512
        )
        try JSONEncoder().encode(customConfig).write(to: manager.configURL, options: .atomic)

        try manager.bootstrapIfNeeded()

        let prompt = try String(contentsOf: manager.promptURL, encoding: .utf8)
        XCTAssertEqual(prompt, "custom prompt")

        let loaded = manager.loadConfig()
        XCTAssertEqual(loaded.claudePath, customConfig.claudePath)
        XCTAssertEqual(loaded.model, customConfig.model)
        XCTAssertEqual(loaded.timeoutSeconds, customConfig.timeoutSeconds)
        XCTAssertEqual(loaded.hotkeyKeyCode, customConfig.hotkeyKeyCode)
        XCTAssertEqual(loaded.hotkeyModifiers, customConfig.hotkeyModifiers)
    }

    func testBootstrapMigratesLegacyDefaultPromptToCurrentDefault() throws {
        let (manager, _) = makeManager()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.baseDirectoryURL, withIntermediateDirectories: true)

        let legacyDefaultPrompt = "Fix the grammar, spelling, and punctuation of the following text. Improve clarity and flow, but keep the tone authentic. Return ONLY the fixed text. Do not add introductory conversational filler."
        try legacyDefaultPrompt.write(to: manager.promptURL, atomically: true, encoding: .utf8)

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
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
    }

    func testLoadConfigAppliesDecoderDefaultsForMissingFields() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "{\"timeoutSeconds\": 12}".write(to: manager.configURL, atomically: true, encoding: .utf8)

        let config = manager.loadConfig()
        XCTAssertEqual(config.timeoutSeconds, 12)
        XCTAssertEqual(config.model, AppConfig.default.model)
        XCTAssertEqual(config.hotkeyKeyCode, AppConfig.default.hotkeyKeyCode)
        XCTAssertEqual(config.hotkeyModifiers, AppConfig.default.hotkeyModifiers)
        XCTAssertEqual(config.claudePath, AppConfig.default.claudePath)
    }

    func testLoadConfigUsesDefaultTimeoutWhenTimeoutMissing() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        try "{\"model\": \"sonnet\"}".write(to: manager.configURL, atomically: true, encoding: .utf8)

        let config = manager.loadConfig()
        XCTAssertEqual(config.model, "sonnet")
        XCTAssertEqual(config.timeoutSeconds, AppConfig.default.timeoutSeconds)
    }

    func testSaveConfigNormalizesTimeoutAndModel() throws {
        let (manager, _) = makeManager()
        try manager.bootstrapIfNeeded()

        let raw = AppConfig(
            claudePath: " /opt/homebrew/bin/claude ",
            model: "   ",
            timeoutSeconds: 1,
            hotkeyKeyCode: 33,
            hotkeyModifiers: 512
        )

        try manager.saveConfig(raw)
        let loaded = manager.loadConfig()

        XCTAssertEqual(loaded.claudePath, raw.claudePath)
        XCTAssertEqual(loaded.model, AppConfig.default.model)
        XCTAssertEqual(loaded.timeoutSeconds, 5)
        XCTAssertEqual(loaded.hotkeyKeyCode, raw.hotkeyKeyCode)
        XCTAssertEqual(loaded.hotkeyModifiers, raw.hotkeyModifiers)
    }

    func testAppConfigResolvedProperties() {
        let config = AppConfig(
            claudePath: "  /usr/local/bin/claude  ",
            model: "   ",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256
        )

        XCTAssertEqual(config.resolvedClaudePath, "/usr/local/bin/claude")
        XCTAssertEqual(config.resolvedModel, AppConfig.default.model)
    }

    func testAppConfigResolvedClaudePathReturnsNilWhenBlank() {
        let config = AppConfig(
            claudePath: " \n\t ",
            model: "haiku",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256
        )

        XCTAssertNil(config.resolvedClaudePath)
    }

    func testDefaultInitializerUsesCurrentUserHomeDirectory() {
        let manager = ConfigManager()
        let expectedBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghostedit", isDirectory: true)
            .path
        XCTAssertEqual(manager.baseDirectoryURL.path, expectedBase)
    }

    private func makeManager() -> (ConfigManager, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-tests-\(UUID().uuidString)", isDirectory: true)
        tempRoots.append(root)
        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: root)
        return (manager, root)
    }
}
