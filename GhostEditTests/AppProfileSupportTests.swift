import XCTest
@testable import GhostEditCore

final class AppProfileSupportTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - resolvedConfig

    func testResolvedConfigNoMatchReturnsBase() {
        let config = AppConfig.default
        let profiles = [AppProfile(bundleIdentifier: "com.other.app", tonePreset: "casual")]
        let result = AppProfileSupport.resolvedConfig(
            base: config,
            profiles: profiles,
            bundleIdentifier: "com.my.app"
        )
        XCTAssertEqual(result.tonePreset, config.tonePreset)
    }

    func testResolvedConfigNilBundleIDReturnsBase() {
        let config = AppConfig.default
        let profiles = [AppProfile(bundleIdentifier: "com.other.app", tonePreset: "casual")]
        let result = AppProfileSupport.resolvedConfig(
            base: config,
            profiles: profiles,
            bundleIdentifier: nil
        )
        XCTAssertEqual(result.tonePreset, config.tonePreset)
    }

    func testResolvedConfigMatchAppliesOverrides() {
        var config = AppConfig.default
        config.tonePreset = "default"
        config.model = "haiku"
        let profiles = [
            AppProfile(bundleIdentifier: "com.slack.Slack", tonePreset: "slack", model: "sonnet", provider: nil)
        ]
        let result = AppProfileSupport.resolvedConfig(
            base: config,
            profiles: profiles,
            bundleIdentifier: "com.slack.Slack"
        )
        XCTAssertEqual(result.tonePreset, "slack")
        XCTAssertEqual(result.model, "sonnet")
        XCTAssertEqual(result.provider, config.provider) // Not overridden
    }

    // MARK: - apply

    func testApplyProfileOverridesTone() {
        var config = AppConfig.default
        config.tonePreset = "default"
        let profile = AppProfile(bundleIdentifier: "test", tonePreset: "professional")
        let result = AppProfileSupport.apply(profile: profile, to: config)
        XCTAssertEqual(result.tonePreset, "professional")
    }

    func testApplyProfileNilFieldsKeepBase() {
        var config = AppConfig.default
        config.model = "opus"
        let profile = AppProfile(bundleIdentifier: "test")
        let result = AppProfileSupport.apply(profile: profile, to: config)
        XCTAssertEqual(result.model, "opus")
        XCTAssertEqual(result.tonePreset, config.tonePreset)
    }

    func testApplyProfileEmptyStringFieldsKeepBase() {
        var config = AppConfig.default
        config.model = "opus"
        let profile = AppProfile(bundleIdentifier: "test", tonePreset: "", model: "", provider: "")
        let result = AppProfileSupport.apply(profile: profile, to: config)
        XCTAssertEqual(result.model, "opus")
        XCTAssertEqual(result.tonePreset, config.tonePreset)
    }

    func testApplyProfileOverridesProvider() {
        var config = AppConfig.default
        config.provider = "claude"
        let profile = AppProfile(bundleIdentifier: "test", provider: "gemini")
        let result = AppProfileSupport.apply(profile: profile, to: config)
        XCTAssertEqual(result.provider, "gemini")
    }

    // MARK: - loadProfiles / saveProfiles

    func testLoadProfilesFromMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let profiles = AppProfileSupport.loadProfiles(from: url)
        XCTAssertEqual(profiles, [])
    }

    func testLoadProfilesFromInvalidJSON() throws {
        let url = tempURL()
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let profiles = AppProfileSupport.loadProfiles(from: url)
        XCTAssertEqual(profiles, [])
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = tempURL()
        let profiles = [
            AppProfile(bundleIdentifier: "com.slack.Slack", tonePreset: "slack"),
            AppProfile(bundleIdentifier: "com.apple.mail", tonePreset: "professional", model: "sonnet"),
        ]

        try AppProfileSupport.saveProfiles(profiles, to: url)
        let loaded = AppProfileSupport.loadProfiles(from: url)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].bundleIdentifier, "com.slack.Slack")
        XCTAssertEqual(loaded[0].tonePreset, "slack")
        XCTAssertEqual(loaded[1].bundleIdentifier, "com.apple.mail")
        XCTAssertEqual(loaded[1].model, "sonnet")
    }

    func testSaveProducesValidJSON() throws {
        let url = tempURL()
        let profiles = [AppProfile(bundleIdentifier: "test")]
        try AppProfileSupport.saveProfiles(profiles, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("bundleIdentifier"))
        XCTAssertTrue(text.contains("\n")) // Pretty-printed
    }

    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profiles-\(UUID().uuidString).json")
        tempURLs.append(url)
        return url
    }
}
