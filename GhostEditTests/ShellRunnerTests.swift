import XCTest
@testable import GhostEditCore

final class ShellRunnerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for root in tempRoots {
            try? fileManager.removeItem(at: root)
        }
        tempRoots.removeAll()
        try super.tearDownWithError()
    }

    func testCorrectTextPassesExpectedArgumentsAndWorkingDirectory() throws {
        let testEnv = try makeRunnerEnvironment()
        let argsLog = testEnv.homeURL.appendingPathComponent("args.log")
        let pwdLog = testEnv.homeURL.appendingPathComponent("pwd.log")

        let script = """
        #!/bin/zsh
        pwd > '\(pwdLog.path)'
        printf '%s\\0' "$@" > '\(argsLog.path)'
        print -r -- "   corrected text   "
        """

        let executable = try makeExecutableScript(named: "claude-ok.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        let output = try testEnv.runner.correctText(
            systemPrompt: "Fix grammar",
            selectedText: "this are wrong"
        )

        XCTAssertEqual(output, "corrected text")

        let argsData = try Data(contentsOf: argsLog)
        let args = argsData
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(args[0], "-p")
        XCTAssertEqual(args[1], "Fix grammar\n\nthis are wrong")
        XCTAssertEqual(args[2], "--setting-sources")
        XCTAssertEqual(args[3], "user")
        XCTAssertEqual(args[4], "--tools")
        XCTAssertEqual(args[5], "")
        XCTAssertEqual(args[6], "--model")
        XCTAssertEqual(args[7], "haiku")

        let workingDirectory = try String(contentsOf: pwdLog, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath().path,
            testEnv.manager.baseDirectoryURL.resolvingSymlinksInPath().path
        )
    }

    func testCorrectTextClassifiesAuthenticationErrorFromStdout() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- 'Failed to authenticate. API Error: 401 {"error":{"message":"OAuth token has expired"}}'
        exit 1
        """

        let executable = try makeExecutableScript(named: "claude-auth-stdout.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case ShellRunnerError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, got: \(error)")
            }
        }
    }

    func testCorrectTextClassifiesAuthenticationErrorFromStderr() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- 'unauthorized request' >&2
        exit 1
        """

        let executable = try makeExecutableScript(named: "claude-auth-stderr.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case ShellRunnerError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, got: \(error)")
            }
        }
    }

    func testCorrectTextFallsBackWithoutModelWhenModelFails() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("calls.log")

        let script = """
        #!/bin/zsh
        print -r -- "CALL" >> '\(callsLog.path)'
        for arg in "$@"; do
          print -r -- "$arg" >> '\(callsLog.path)'
        done
        print -r -- "---" >> '\(callsLog.path)'

        if [[ " $* " == *" --model "* ]]; then
          print -r -- "unsupported model" >&2
          exit 7
        fi

        print -r -- "fallback ok"
        """

        let executable = try makeExecutableScript(named: "claude-fallback.sh", contents: script, homeURL: testEnv.homeURL)
        let customConfig = AppConfig(
            claudePath: executable.path,
            model: "custom-model",
            timeoutSeconds: 30,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256
        )
        try testEnv.manager.saveConfig(customConfig)

        let output = try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        XCTAssertEqual(output, "fallback ok")

        let calls = try String(contentsOf: callsLog, encoding: .utf8)
        let callCount = calls.components(separatedBy: "CALL").count - 1
        XCTAssertEqual(callCount, 2)
        XCTAssertTrue(calls.contains("--model"))
    }

    func testCorrectTextUsesStdoutDetailsWhenStderrIsEmpty() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- 'detailed failure message'
        exit 2
        """

        let executable = try makeExecutableScript(named: "claude-failure-stdout.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.processFailed(exitCode, stderr) = error else {
                return XCTFail("Expected processFailed, got: \(error)")
            }
            XCTAssertEqual(exitCode, 2)
            XCTAssertTrue(stderr.contains("detailed failure message"))
        }
    }

    func testCorrectTextThrowsEmptyResponseWhenClaudeReturnsWhitespace() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- '   '
        exit 0
        """

        let executable = try makeExecutableScript(named: "claude-empty.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case ShellRunnerError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got: \(error)")
            }
        }
    }

    func testResolveClaudePathSearchesAndCachesDiscoveredPath() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let discoveredPath = "\(homeURL.path)/.local/bin/claude"
        let fileManager = StubExecutableFileManager(executablePaths: [discoveredPath])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: ["PATH": "/custom/bin"],
            homeDirectoryPath: homeURL.path
        )

        let first = try runner.resolveClaudePath(preferredPath: "/definitely/missing/claude")
        XCTAssertEqual(first, discoveredPath)
        let firstCallCount = fileManager.callCount

        let second = try runner.resolveClaudePath(preferredPath: nil)
        XCTAssertEqual(second, discoveredPath)
        XCTAssertEqual(fileManager.callCount, firstCallCount + 1)
        XCTAssertEqual(fileManager.queriedPaths.last, discoveredPath)
    }

    func testResolveClaudePathThrowsNotFoundWhenNoExecutableExists() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let fileManager = StubExecutableFileManager(executablePaths: [])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: [:],
            homeDirectoryPath: homeURL.path
        )

        XCTAssertThrowsError(try runner.resolveClaudePath(preferredPath: nil)) { error in
            guard case ShellRunnerError.claudeNotFound = error else {
                return XCTFail("Expected claudeNotFound, got: \(error)")
            }
        }
    }

    func testPrewarmAttemptsBackgroundPathResolution() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let discoveredPath = "\(homeURL.path)/.local/bin/claude"
        let fileManager = StubExecutableFileManager(executablePaths: [discoveredPath])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: [:],
            homeDirectoryPath: homeURL.path
        )

        runner.prewarm()

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && fileManager.callCount == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertGreaterThan(fileManager.callCount, 0)
        XCTAssertTrue(fileManager.queriedPaths.contains(discoveredPath))
    }

    func testCorrectTextThrowsLaunchFailedWhenExecutableCannotStart() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/no/such/interpreter
        print -r -- "won't run"
        """

        let executable = try makeExecutableScript(named: "claude-launch-fail.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.launchFailed(message) = error else {
                return XCTFail("Expected launchFailed, got: \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testCorrectTextThrowsTimedOutWhenClaudeHangs() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        sleep 6
        print -r -- "too late"
        """

        let executable = try makeExecutableScript(named: "claude-timeout.sh", contents: script, homeURL: testEnv.homeURL)
        let config = AppConfig(
            claudePath: executable.path,
            model: "custom-model",
            timeoutSeconds: 1,
            hotkeyKeyCode: 14,
            hotkeyModifiers: 256
        )
        try testEnv.manager.saveConfig(config)

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.timedOut(seconds) = error else {
                return XCTFail("Expected timedOut, got: \(error)")
            }
            XCTAssertEqual(seconds, 5)
        }
    }

    func testCorrectTextHandlesInvalidUTF8OutputStreams() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        printf '\\377'
        printf '\\377' >&2
        exit 2
        """

        let executable = try makeExecutableScript(named: "claude-invalid-utf8.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(AppConfig.default.withClaudePath(executable.path))

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.processFailed(exitCode, stderr) = error else {
                return XCTFail("Expected processFailed, got: \(error)")
            }
            XCTAssertEqual(exitCode, 2)
            XCTAssertEqual(stderr, "")
        }
    }

    func testShellRunnerErrorDescriptions() {
        XCTAssertEqual(
            ShellRunnerError.claudeNotFound.errorDescription,
            "The claude CLI could not be found. Set an absolute path in ~/.ghostedit/config.json."
        )
        XCTAssertEqual(
            ShellRunnerError.authenticationRequired.errorDescription,
            "Claude authentication has expired. Run `claude auth login` in Terminal, then try again."
        )
        XCTAssertEqual(
            ShellRunnerError.launchFailed("boom").errorDescription,
            "Failed to start claude: boom"
        )
        XCTAssertEqual(
            ShellRunnerError.processFailed(exitCode: 17, stderr: "details here").errorDescription,
            "claude exited with code 17: details here"
        )
        XCTAssertEqual(
            ShellRunnerError.processFailed(exitCode: 17, stderr: "   \n  ").errorDescription,
            "claude exited with code 17."
        )
        XCTAssertEqual(
            ShellRunnerError.timedOut(seconds: 8).errorDescription,
            "claude timed out after 8 seconds."
        )
        XCTAssertEqual(
            ShellRunnerError.emptyResponse.errorDescription,
            "claude returned an empty response."
        )
    }

    private func makeRunnerEnvironment() throws -> (homeURL: URL, manager: ConfigManager, runner: ShellRunner) {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostedit-shellrunner-tests-\(UUID().uuidString)", isDirectory: true)
        tempRoots.append(homeURL)

        let manager = ConfigManager(fileManager: .default, homeDirectoryURL: homeURL)
        try manager.bootstrapIfNeeded()
        let runner = ShellRunner(configManager: manager)
        return (homeURL, manager, runner)
    }

    private func makeExecutableScript(named name: String, contents: String, homeURL: URL) throws -> URL {
        let scriptURL = homeURL.appendingPathComponent(name)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}

private extension AppConfig {
    func withClaudePath(_ path: String) -> AppConfig {
        AppConfig(
            claudePath: path,
            model: model,
            timeoutSeconds: timeoutSeconds,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers
        )
    }
}

private final class StubExecutableFileManager: FileManager {
    private let lock = NSLock()

    var executablePaths: Set<String>
    private(set) var queriedPaths: [String] = []

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        lock.lock()
        queriedPaths.append(path)
        let isExecutable = executablePaths.contains(path)
        lock.unlock()
        return isExecutable
    }

    var callCount: Int {
        lock.lock()
        let count = queriedPaths.count
        lock.unlock()
        return count
    }
}
