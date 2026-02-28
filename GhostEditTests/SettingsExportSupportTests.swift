import XCTest
@testable import GhostEditCore

final class SettingsExportSupportTests: XCTestCase {
    func testExportAndImportRoundTrip() throws {
        let config = AppConfig.default
        let prompt = "Fix grammar"
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let data = try SettingsExportSupport.exportSettings(
            config: config,
            prompt: prompt,
            appVersion: "4.2.0",
            now: now
        )

        let imported = try SettingsExportSupport.importSettings(from: data)
        XCTAssertEqual(imported.config, config)
        XCTAssertEqual(imported.prompt, prompt)
        XCTAssertEqual(imported.appVersion, "4.2.0")
        XCTAssertEqual(imported.exportedAt, now)
    }

    func testExportProducesPrettyJSON() throws {
        let data = try SettingsExportSupport.exportSettings(
            config: .default,
            prompt: "test",
            appVersion: "1.0"
        )
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\n"))
        XCTAssertTrue(text.contains("\"config\""))
        XCTAssertTrue(text.contains("\"prompt\""))
        XCTAssertTrue(text.contains("\"appVersion\""))
        XCTAssertTrue(text.contains("\"exportedAt\""))
    }

    func testImportFromInvalidDataThrows() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try SettingsExportSupport.importSettings(from: data))
    }

    func testImportFromEmptyDataThrows() {
        let data = Data()
        XCTAssertThrowsError(try SettingsExportSupport.importSettings(from: data))
    }

    func testDefaultFileNameContainsDate() {
        let name = SettingsExportSupport.defaultFileName(appVersion: "4.2.0")
        XCTAssertTrue(name.hasPrefix("ghostedit-settings-"))
        XCTAssertTrue(name.hasSuffix(".json"))
    }

    func testImportPreservesCustomConfig() throws {
        var config = AppConfig.default
        config.provider = "gemini"
        config.model = "gemini-2.5-pro"
        config.timeoutSeconds = 120
        config.language = "fr"
        config.tonePreset = "academic"

        let data = try SettingsExportSupport.exportSettings(
            config: config,
            prompt: "Custom prompt here",
            appVersion: "4.2.0"
        )

        let imported = try SettingsExportSupport.importSettings(from: data)
        XCTAssertEqual(imported.config.provider, "gemini")
        XCTAssertEqual(imported.config.model, "gemini-2.5-pro")
        XCTAssertEqual(imported.config.timeoutSeconds, 120)
        XCTAssertEqual(imported.config.language, "fr")
        XCTAssertEqual(imported.config.tonePreset, "academic")
        XCTAssertEqual(imported.prompt, "Custom prompt here")
    }
}
