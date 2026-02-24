import XCTest
@testable import GhostEditCore

final class DeveloperModeSupportTests: XCTestCase {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func testFormatEntryIncludesTimestampPhaseAndMessage() {
        let date = Date(timeIntervalSince1970: 0)
        let entry = DeveloperModeLogEntry(phase: .cliExecution, message: "hello", timestamp: date)
        let result = DeveloperModeSupport.formatEntry(entry, formatter: formatter)
        XCTAssertTrue(result.contains("[CLI_EXECUTION]"))
        XCTAssertTrue(result.contains("hello"))
    }

    func testFormatAllEntriesJoinsWithNewlines() {
        let date = Date(timeIntervalSince1970: 0)
        let entries = [
            DeveloperModeLogEntry(phase: .textCapture, message: "a", timestamp: date),
            DeveloperModeLogEntry(phase: .cliResponse, message: "b", timestamp: date)
        ]
        let result = DeveloperModeSupport.formatAllEntries(entries, formatter: formatter)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("[TEXT_CAPTURE]"))
        XCTAssertTrue(lines[1].contains("[CLI_RESPONSE]"))
    }

    func testFormatAllEntriesReturnsEmptyStringForEmptyArray() {
        let result = DeveloperModeSupport.formatAllEntries([], formatter: formatter)
        XCTAssertEqual(result, "")
    }

    func testPhaseIconReturnsUniqueIconForEachPhase() {
        let icons = DeveloperModeLogEntry.Phase.allCases.map {
            DeveloperModeSupport.phaseIcon(for: $0)
        }
        XCTAssertEqual(icons.count, 7)
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .textCapture), ">")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .tokenProtection), "#")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .cliResolution), "?")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .cliExecution), "$")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .cliResponse), "<")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .tokenRestoration), "=")
        XCTAssertEqual(DeveloperModeSupport.phaseIcon(for: .pasteBack), "^")
    }

    func testTruncateReturnsFullTextWhenUnderLimit() {
        let text = "short text"
        XCTAssertEqual(DeveloperModeSupport.truncate(text, maxLength: 200), text)
    }

    func testTruncateReturnsFullTextWhenExactlyAtLimit() {
        let text = String(repeating: "a", count: 200)
        XCTAssertEqual(DeveloperModeSupport.truncate(text, maxLength: 200), text)
    }

    func testTruncateTrimsLongTextWithEllipsis() {
        let text = String(repeating: "x", count: 250)
        let result = DeveloperModeSupport.truncate(text, maxLength: 200)
        XCTAssertEqual(result.count, 203) // 200 + "..."
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testTruncateUsesDefaultMaxLength() {
        let text = String(repeating: "y", count: 300)
        let result = DeveloperModeSupport.truncate(text)
        XCTAssertEqual(result.count, 203) // 200 + "..."
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testTruncateReturnsEmptyStringForEmptyInput() {
        XCTAssertEqual(DeveloperModeSupport.truncate(""), "")
    }

    func testWindowAndLayoutConstants() {
        XCTAssertEqual(DeveloperModeSupport.windowWidth, 700)
        XCTAssertEqual(DeveloperModeSupport.windowHeight, 480)
        XCTAssertEqual(DeveloperModeSupport.maxEntries, 5000)
    }

    func testDeveloperModeLogEntryEquality() {
        let date = Date(timeIntervalSince1970: 100)
        let a = DeveloperModeLogEntry(phase: .cliExecution, message: "msg", timestamp: date)
        let b = DeveloperModeLogEntry(phase: .cliExecution, message: "msg", timestamp: date)
        let c = DeveloperModeLogEntry(phase: .cliResponse, message: "msg", timestamp: date)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testPhaseRawValues() {
        XCTAssertEqual(DeveloperModeLogEntry.Phase.textCapture.rawValue, "TEXT_CAPTURE")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.tokenProtection.rawValue, "TOKEN_PROTECTION")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.cliResolution.rawValue, "CLI_RESOLUTION")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.cliExecution.rawValue, "CLI_EXECUTION")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.cliResponse.rawValue, "CLI_RESPONSE")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.tokenRestoration.rawValue, "TOKEN_RESTORATION")
        XCTAssertEqual(DeveloperModeLogEntry.Phase.pasteBack.rawValue, "PASTE_BACK")
    }

    func testAllPhaseCasesAreCovered() {
        let allCases = DeveloperModeLogEntry.Phase.allCases
        XCTAssertEqual(allCases.count, 7)
    }

    func testLogEntryDefaultTimestamp() {
        let before = Date()
        let entry = DeveloperModeLogEntry(phase: .textCapture, message: "test")
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testDeveloperModeLoggerProtocolConformance() {
        let spy = SpyLogger()
        let entry = DeveloperModeLogEntry(phase: .cliExecution, message: "test")
        spy.log(entry)
        XCTAssertEqual(spy.entries.count, 1)
        XCTAssertEqual(spy.entries.first, entry)
    }

    func testShellRunnerDevLogCallsLoggerWhenSet() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-devlog-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: tempRoot)
        try manager.bootstrapIfNeeded()

        let script = """
        #!/bin/zsh
        print -r -- "dev corrected"
        """
        let scriptURL = tempRoot.appendingPathComponent("claude-dev.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var config = AppConfig.default
        config.claudePath = scriptURL.path
        config.developerMode = true
        try manager.saveConfig(config)

        let spy = SpyLogger()
        let runner = ShellRunner(configManager: manager)
        runner.developerModeLogger = spy

        _ = try runner.correctText(systemPrompt: "Fix", selectedText: "test")

        XCTAssertGreaterThan(spy.entries.count, 0)
        let phases = Set(spy.entries.map { $0.phase })
        XCTAssertTrue(phases.contains(.cliResolution))
        XCTAssertTrue(phases.contains(.cliExecution))
        XCTAssertTrue(phases.contains(.cliResponse))
    }

    func testShellRunnerDevLogDoesNotCallLoggerWhenNil() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-devlog-nil-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: tempRoot)
        try manager.bootstrapIfNeeded()

        let script = """
        #!/bin/zsh
        print -r -- "no logger"
        """
        let scriptURL = tempRoot.appendingPathComponent("claude-nolog.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var config = AppConfig.default
        config.claudePath = scriptURL.path
        try manager.saveConfig(config)

        let runner = ShellRunner(configManager: manager)
        // No logger set — should not crash
        let output = try runner.correctText(systemPrompt: "Fix", selectedText: "test")
        XCTAssertEqual(output, "no logger")
    }

    func testAppConfigDeveloperModeDefaultIsFalse() {
        XCTAssertFalse(AppConfig.default.developerMode)
    }

    func testAppConfigDeveloperModeRoundTrips() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-devmode-cfg-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: tempRoot)
        try manager.bootstrapIfNeeded()

        var config = manager.loadConfig()
        XCTAssertFalse(config.developerMode)

        config.developerMode = true
        try manager.saveConfig(config)

        manager.invalidateCache()
        let reloaded = manager.loadConfig()
        XCTAssertTrue(reloaded.developerMode)
    }

    func testAppConfigDeveloperModeDecodesFromJSON() throws {
        let json = """
        {"developerMode": true, "provider": "claude"}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertTrue(config.developerMode)
    }

    func testAppConfigDeveloperModeDefaultsWhenMissingFromJSON() throws {
        let json = """
        {"provider": "claude"}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertFalse(config.developerMode)
    }

    func testShellRunnerLogsTokenPreservationPhases() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-token-devlog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: tempRoot)
        try manager.bootstrapIfNeeded()

        let script = """
        #!/bin/zsh
        print -r -- "Hello __GHOSTEDIT_KEEP_0__."
        """
        let scriptURL = tempRoot.appendingPathComponent("claude-token-dev.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var config = AppConfig.default
        config.claudePath = scriptURL.path
        config.developerMode = true
        try manager.saveConfig(config)

        let spy = SpyLogger()
        let runner = ShellRunner(configManager: manager)
        runner.developerModeLogger = spy

        let result = try runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "hello @<U1>"
        )
        XCTAssertEqual(result, "Hello @<U1>.")

        let phases = Set(spy.entries.map { $0.phase })
        XCTAssertTrue(phases.contains(.tokenProtection))
        XCTAssertTrue(phases.contains(.tokenRestoration))
    }
}

private final class SpyLogger: DeveloperModeLogger {
    private(set) var entries: [DeveloperModeLogEntry] = []

    func log(_ entry: DeveloperModeLogEntry) {
        entries.append(entry)
    }
}
