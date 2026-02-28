import XCTest
@testable import GhostEditCore

final class SettingsValidationIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var configManager: ConfigManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configManager = ConfigManager(homeDirectoryURL: tempDir)
        try? configManager.bootstrapIfNeeded()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoadPreservesAllValidatedSettings() throws {
        // Validate settings
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: 14, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 15, cloudHotkeyModifiers: 768,
            selectedOptionValue: "claude-3", customModel: "claude-3-opus",
            historyLimitText: "200", timeoutText: "45", diffPreviewDurationText: "10"
        )

        guard case .success(let validated) = result else {
            XCTFail("Validation should succeed")
            return
        }

        // Apply to config and save
        var config = configManager.loadConfig()
        config.hotkeyKeyCode = validated.hotkeyKeyCode
        config.hotkeyModifiers = validated.hotkeyModifiers
        config.cloudHotkeyKeyCode = validated.cloudHotkeyKeyCode
        config.cloudHotkeyModifiers = validated.cloudHotkeyModifiers
        config.model = validated.model
        config.historyLimit = validated.historyLimit
        config.timeoutSeconds = validated.timeoutSeconds
        config.diffPreviewDuration = validated.diffPreviewDuration
        try configManager.saveConfig(config)

        // Invalidate cache so we read from disk
        configManager.invalidateCache()

        // Load and verify round-trip
        let loaded = configManager.loadConfig()
        XCTAssertEqual(loaded.hotkeyKeyCode, 14)
        XCTAssertEqual(loaded.hotkeyModifiers, 256)
        XCTAssertEqual(loaded.cloudHotkeyKeyCode, 15)
        XCTAssertEqual(loaded.cloudHotkeyModifiers, 768)
        XCTAssertEqual(loaded.model, "claude-3-opus")
        XCTAssertEqual(loaded.historyLimit, 200)
        XCTAssertEqual(loaded.timeoutSeconds, 45)
        XCTAssertEqual(loaded.diffPreviewDuration, 10)
    }

    func testValidationCascadeStopsAtFirstError() {
        // Missing hotkey key code — should fail immediately
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: nil, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 15, cloudHotkeyModifiers: 768,
            selectedOptionValue: "model", customModel: "claude-3",
            historyLimitText: "abc", timeoutText: "2", diffPreviewDurationText: "0"
        )
        if case .failure(let error) = result {
            // Should fail on first check (hotkey key code), not on later ones
            XCTAssertEqual(error.title, "Hotkey key is required")
        } else {
            XCTFail("Should have failed")
        }
    }

    func testModifierBitmaskRoundTrip() {
        let modifiers = SettingsValidationSupport.buildHotkeyModifiers(
            command: true, option: false, control: true, shift: false
        )
        let (cmd, opt, ctrl, shift) = SettingsValidationSupport.splitHotkeyModifiers(modifiers)
        XCTAssertTrue(cmd)
        XCTAssertFalse(opt)
        XCTAssertTrue(ctrl)
        XCTAssertFalse(shift)
    }

    func testConfigDefaultsAreValid() {
        let config = configManager.loadConfig()
        // Default settings should pass validation
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: config.hotkeyKeyCode,
            hotkeyModifiers: config.hotkeyModifiers,
            cloudHotkeyKeyCode: config.cloudHotkeyKeyCode,
            cloudHotkeyModifiers: config.cloudHotkeyModifiers,
            selectedOptionValue: config.model.isEmpty ? nil : config.model,
            customModel: config.model,
            historyLimitText: "\(config.historyLimit)",
            timeoutText: "\(config.timeoutSeconds)",
            diffPreviewDurationText: "\(config.diffPreviewDuration)"
        )
        if case .failure(let error) = result {
            XCTFail("Default config should validate: \(error.title)")
        }
    }

    func testHistoryTrimOnLimitChange() throws {
        let store = CorrectionHistoryStore(fileURL: configManager.historyURL)

        // Add entries
        for i in 0..<10 {
            try store.append(CorrectionHistoryEntry(
                id: UUID(),
                timestamp: Date().addingTimeInterval(Double(-i)),
                originalText: "original \(i)",
                generatedText: "corrected \(i)",
                provider: "test",
                model: "test",
                durationMilliseconds: 100,
                succeeded: true
            ), limit: 100)
        }

        let allEntries = store.load()
        XCTAssertEqual(allEntries.count, 10)

        // Trim to 5
        try store.trim(limit: 5)
        let trimmed = store.load()
        XCTAssertEqual(trimmed.count, 5)
    }
}
