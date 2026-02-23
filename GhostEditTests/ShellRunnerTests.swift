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

    func testCorrectTextStripsClaudeCodeEnvironmentVariables() throws {
        let testEnv = try makeRunnerEnvironment()
        let envLog = testEnv.homeURL.appendingPathComponent("env.log")

        let script = """
        #!/bin/zsh
        env > '\(envLog.path)'
        print -r -- "ok"
        """

        let executable = try makeExecutableScript(named: "claude-env-check.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        // Create a new runner with CLAUDECODE and CLAUDE_CODE set in the environment.
        let injectedEnv = [
            "CLAUDECODE": "1",
            "CLAUDE_CODE": "1",
            "HOME": testEnv.homeURL.path,
        ]
        let runner = ShellRunner(
            configManager: testEnv.manager,
            environment: injectedEnv,
            homeDirectoryPath: testEnv.homeURL.path
        )

        let output = try runner.correctText(systemPrompt: "p", selectedText: "x")
        XCTAssertEqual(output, "ok")

        let envOutput = try String(contentsOf: envLog, encoding: .utf8)
        XCTAssertFalse(envOutput.contains("CLAUDECODE="), "CLAUDECODE should be stripped from the child process environment")
        XCTAssertFalse(envOutput.contains("CLAUDE_CODE="), "CLAUDE_CODE should be stripped from the child process environment")
    }

    func testCorrectTextPassesExpectedArgumentsAndWorkingDirectoryForClaude() throws {
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
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let output = try testEnv.runner.correctText(
            systemPrompt: "Fix grammar",
            selectedText: "this are wrong"
        )

        XCTAssertEqual(output, "corrected text")

        let argsData = try Data(contentsOf: argsLog)
        let args = decodeNullSeparatedArguments(from: argsData)
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

    func testCorrectTextPassesExpectedArgumentsForCodex() throws {
        let testEnv = try makeRunnerEnvironment()
        let argsLog = testEnv.homeURL.appendingPathComponent("codex-args.log")

        let script = """
        #!/bin/zsh
        printf '%s\\0' "$@" > '\(argsLog.path)'
        print -r -- "codex corrected"
        """

        let executable = try makeExecutableScript(named: "codex-ok.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.codex, executablePath: executable.path, model: "gpt-5-codex")
        )

        let output = try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        XCTAssertEqual(output, "codex corrected")

        let argsData = try Data(contentsOf: argsLog)
        let args = decodeNullSeparatedArguments(from: argsData)
        XCTAssertEqual(args, [
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "-c",
            "model_reasoning_effort='low'",
            "--model",
            "gpt-5-codex",
            "p\n\nx"
        ])
    }

    func testCorrectTextPassesExpectedArgumentsForGemini() throws {
        let testEnv = try makeRunnerEnvironment()
        let argsLog = testEnv.homeURL.appendingPathComponent("gemini-args.log")

        let script = """
        #!/bin/zsh
        printf '%s\\0' "$@" > '\(argsLog.path)'
        print -r -- "gemini corrected"
        """

        let executable = try makeExecutableScript(named: "gemini-ok.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.gemini, executablePath: executable.path, model: "gemini-2.5-flash")
        )

        let output = try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        XCTAssertEqual(output, "gemini corrected")

        let argsData = try Data(contentsOf: argsLog)
        let args = decodeNullSeparatedArguments(from: argsData)
        XCTAssertEqual(args, [
            "--prompt",
            "p\n\nx",
            "--output-format",
            "text",
            "--model",
            "gemini-2.5-flash"
        ])
    }

    func testCorrectTextPreservingTokensFallsBackToNormalFlowWhenNoProtectedTokens() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- "plain corrected text"
        """
        let executable = try makeExecutableScript(named: "plain-correct.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let output = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "this are plain text"
        )
        XCTAssertEqual(output, "plain corrected text")
    }

    func testCorrectTextPreservingTokensRestoresMentionsAndEmoji() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- "Please check with __GHOSTEDIT_KEEP_0__ and then add __GHOSTEDIT_KEEP_1__."
        """
        let executable = try makeExecutableScript(named: "preserve-tokens.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let output = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "pls check with @<U123ABC> and add :hat:"
        )
        XCTAssertEqual(output, "Please check with @<U123ABC> and then add :hat:.")
    }

    func testCorrectTextPreservingTokensRestoresAtNameAndFilePath() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- "Please ask __GHOSTEDIT_KEEP_0__ to review __GHOSTEDIT_KEEP_1__."
        """
        let executable = try makeExecutableScript(named: "preserve-static.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let output = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "pls ask @naresh to review /tmp/report.txt"
        )
        XCTAssertEqual(output, "Please ask @naresh to review /tmp/report.txt.")
    }

    func testCorrectTextPreservingTokensRetriesOnceWhenPlaceholderMissing() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("token-retry.log")
        let script = """
        #!/bin/zsh
        count=0
        if [[ -f '\(callsLog.path)' ]]; then
          count=$(cat '\(callsLog.path)')
        fi
        count=$((count + 1))
        print -r -- "$count" > '\(callsLog.path)'

        if [[ "$count" -eq 1 ]]; then
          print -r -- "First pass forgot placeholder."
        else
          print -r -- "Second pass keeps __GHOSTEDIT_KEEP_0__."
        fi
        """
        let executable = try makeExecutableScript(named: "preserve-retry.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let output = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "hello @<U99>"
        )
        XCTAssertEqual(output, "Second pass keeps @<U99>.")
        let attempts = try String(contentsOf: callsLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(attempts, "2")
    }

    func testCorrectTextPreservingTokensRetryPreservesEmojisWithOriginalText() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("token-aware.log")
        // With maxValidationRetries: 0:
        //   Call 1: placeholder attempt — AI strips placeholders.
        //   Call 2: token-aware retry with original text — AI preserves emojis.
        let script = """
        #!/bin/zsh
        count=0
        if [[ -f '\(callsLog.path)' ]]; then
          count=$(cat '\(callsLog.path)')
        fi
        count=$((count + 1))
        print -r -- "$count" > '\(callsLog.path)'

        if [[ "$count" -le 1 ]]; then
          print -r -- "Placeholders stripped by AI."
        else
          print -r -- "Hello :sad: and :mad: about the delay."
        fi
        """
        let executable = try makeExecutableScript(named: "token-aware.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let result = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "hello :sad: and :mad: about the delay",
            maxValidationRetries: 0
        )
        XCTAssertEqual(result, "Hello :sad: and :mad: about the delay.")
    }

    func testCorrectTextPreservingTokensRetryPreservesAllTokenTypes() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("token-types.log")
        let script = """
        #!/bin/zsh
        count=0
        if [[ -f '\(callsLog.path)' ]]; then
          count=$(cat '\(callsLog.path)')
        fi
        count=$((count + 1))
        print -r -- "$count" > '\(callsLog.path)'

        if [[ "$count" -le 1 ]]; then
          print -r -- "Stripped all placeholders."
        else
          print -r -- "Please ask @naresh about :hat: at /tmp/report.txt."
        fi
        """
        let executable = try makeExecutableScript(named: "token-types.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let result = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "pls ask @naresh about :hat: at /tmp/report.txt",
            maxValidationRetries: 0
        )
        XCTAssertEqual(result, "Please ask @naresh about :hat: at /tmp/report.txt.")
    }

    func testCorrectTextPreservingTokensFallsBackToBestEffortWhenRetryAlsoFails() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("both-fail.log")
        // Both placeholder and token-aware retry return text without tokens.
        let script = """
        #!/bin/zsh
        count=0
        if [[ -f '\(callsLog.path)' ]]; then
          count=$(cat '\(callsLog.path)')
        fi
        count=$((count + 1))
        print -r -- "$count" > '\(callsLog.path)'

        if [[ "$count" -le 1 ]]; then
          print -r -- "Completely rewritten text."
        else
          print -r -- "Totally different output."
        fi
        """
        let executable = try makeExecutableScript(named: "both-fail.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        // When the token-aware retry also loses tokens, falls back to best-effort.
        let result = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "hello :wave: world",
            maxValidationRetries: 0
        )
        // bestEffortRestore on "Completely rewritten text." — no placeholders survive.
        XCTAssertEqual(result, "Completely rewritten text.")
    }

    func testCorrectTextPreservingTokensRestoresPartialSurvivors() throws {
        let testEnv = try makeRunnerEnvironment()
        let callsLog = testEnv.homeURL.appendingPathComponent("partial.log")
        // Call 1: AI keeps placeholder 0 but strips placeholder 1.
        // Call 2: token-aware retry — only one of two tokens survives.
        let script = """
        #!/bin/zsh
        count=0
        if [[ -f '\(callsLog.path)' ]]; then
          count=$(cat '\(callsLog.path)')
        fi
        count=$((count + 1))
        print -r -- "$count" > '\(callsLog.path)'

        if [[ "$count" -le 1 ]]; then
          print -r -- "Hello __GHOSTEDIT_KEEP_0__ world."
        else
          print -r -- "Hello @<U1> world without emoji."
        fi
        """
        let executable = try makeExecutableScript(named: "preserve-partial.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "haiku")
        )

        let result = try testEnv.runner.correctTextPreservingTokens(
            systemPrompt: "Fix grammar",
            selectedText: "hello @<U1> :sad:",
            maxValidationRetries: 0
        )
        // Token-aware retry has @<U1> but not :sad: → allSatisfy fails.
        // Falls back to best-effort on placeholder attempt: @<U1> restored, :sad: lost.
        XCTAssertEqual(result, "Hello @<U1> world.")
    }

    func testCorrectTextClassifiesAuthenticationErrorFromStdout() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- 'Failed to authenticate. API Error: 401 {"error":{"message":"OAuth token has expired"}}'
        exit 1
        """

        let executable = try makeExecutableScript(named: "cli-auth-stdout.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path)
        )

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.authenticationRequired(provider) = error else {
                return XCTFail("Expected authenticationRequired, got: \(error)")
            }
            XCTAssertEqual(provider, .claude)
        }
    }

    func testCorrectTextClassifiesAuthenticationErrorFromStderr() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- 'please run codex login' >&2
        exit 1
        """

        let executable = try makeExecutableScript(named: "cli-auth-stderr.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.codex, executablePath: executable.path)
        )

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.authenticationRequired(provider) = error else {
                return XCTFail("Expected authenticationRequired, got: \(error)")
            }
            XCTAssertEqual(provider, .codex)
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

        let executable = try makeExecutableScript(named: "cli-fallback.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path, model: "custom-model")
        )

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

        let executable = try makeExecutableScript(named: "cli-failure-stdout.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.gemini, executablePath: executable.path)
        )

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

    func testCorrectTextThrowsEmptyResponseWhenCLIReturnsWhitespace() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        print -r -- '   '
        exit 0
        """

        let executable = try makeExecutableScript(named: "cli-empty.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.codex, executablePath: executable.path, model: "")
        )

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case ShellRunnerError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got: \(error)")
            }
        }
    }

    func testResolveCLIPathSearchesAndCachesDiscoveredPath() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let discoveredPath = "\(homeURL.path)/.local/bin/codex"
        let fileManager = StubExecutableFileManager(executablePaths: [discoveredPath])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: ["PATH": "/custom/bin"],
            homeDirectoryPath: homeURL.path
        )

        let first = try runner.resolveCLIPath(provider: .codex, preferredPath: "/definitely/missing/codex")
        XCTAssertEqual(first, discoveredPath)
        let firstCallCount = fileManager.callCount

        let second = try runner.resolveCLIPath(provider: .codex, preferredPath: nil)
        XCTAssertEqual(second, discoveredPath)
        XCTAssertEqual(fileManager.callCount, firstCallCount + 1)
        XCTAssertEqual(fileManager.queriedPaths.last, discoveredPath)
    }

    func testResolveClaudePathWrapperUsesClaudeProvider() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let discoveredPath = "\(homeURL.path)/.local/bin/claude"
        let fileManager = StubExecutableFileManager(executablePaths: [discoveredPath])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: [:],
            homeDirectoryPath: homeURL.path
        )

        XCTAssertEqual(try runner.resolveClaudePath(preferredPath: nil), discoveredPath)
    }

    func testResolveCLIPathThrowsNotFoundWhenNoExecutableExists() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let fileManager = StubExecutableFileManager(executablePaths: [])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: [:],
            homeDirectoryPath: homeURL.path
        )

        XCTAssertThrowsError(
            try runner.resolveCLIPath(provider: .gemini, preferredPath: nil)
        ) { error in
            guard case let ShellRunnerError.cliNotFound(provider) = error else {
                return XCTFail("Expected cliNotFound, got: \(error)")
            }
            XCTAssertEqual(provider, .gemini)
        }
    }

    func testPrewarmAttemptsBackgroundPathResolution() throws {
        let (homeURL, manager, _) = try makeRunnerEnvironment()
        let discoveredPath = "\(homeURL.path)/.local/bin/gemini"
        let fileManager = StubExecutableFileManager(executablePaths: [discoveredPath])
        let runner = ShellRunner(
            configManager: manager,
            fileManager: fileManager,
            environment: [:],
            homeDirectoryPath: homeURL.path
        )

        try manager.saveConfig(
            AppConfig.default.withProvider(.gemini, executablePath: discoveredPath, model: "")
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

        let executable = try makeExecutableScript(named: "cli-launch-fail.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.claude, executablePath: executable.path)
        )

        XCTAssertThrowsError(
            try testEnv.runner.correctText(systemPrompt: "p", selectedText: "x")
        ) { error in
            guard case let ShellRunnerError.launchFailed(message) = error else {
                return XCTFail("Expected launchFailed, got: \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testCorrectTextThrowsTimedOutWhenCLIHangs() throws {
        let testEnv = try makeRunnerEnvironment()
        let script = """
        #!/bin/zsh
        sleep 6
        print -r -- "too late"
        """

        let executable = try makeExecutableScript(named: "cli-timeout.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(
                .gemini,
                executablePath: executable.path,
                model: "gemini-2.5-flash",
                timeoutSeconds: 1
            )
        )

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

        let executable = try makeExecutableScript(named: "cli-invalid-utf8.sh", contents: script, homeURL: testEnv.homeURL)
        try testEnv.manager.saveConfig(
            AppConfig.default.withProvider(.codex, executablePath: executable.path, model: "")
        )

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
            ShellRunnerError.cliNotFound(provider: .claude).errorDescription,
            "The claude CLI could not be found. Set an absolute path in ~/.ghostedit/config.json or switch provider in Settings."
        )
        XCTAssertEqual(
            ShellRunnerError.authenticationRequired(provider: .codex).errorDescription,
            "Codex authentication has expired. Run `codex login` in Terminal, then try again."
        )
        XCTAssertEqual(
            ShellRunnerError.launchFailed("boom").errorDescription,
            "Failed to start CLI process: boom"
        )
        XCTAssertEqual(
            ShellRunnerError.processFailed(exitCode: 17, stderr: "details here").errorDescription,
            "CLI exited with code 17: details here\nTry switching the model in Settings if this model is busy or unavailable."
        )
        XCTAssertEqual(
            ShellRunnerError.processFailed(exitCode: 17, stderr: "   \n  ").errorDescription,
            "CLI exited with code 17. Try switching the model in Settings if the selected model is busy."
        )
        XCTAssertEqual(
            ShellRunnerError.timedOut(seconds: 8).errorDescription,
            "CLI timed out after 8 seconds. Try switching the model in Settings if the selected model is busy."
        )
        XCTAssertEqual(
            ShellRunnerError.emptyResponse.errorDescription,
            "CLI returned an empty response. Try switching the model in Settings."
        )
        XCTAssertEqual(
            ShellRunnerError.protectedTokensModified.errorDescription,
            "The AI response changed protected static tokens. Retried once, but placeholders were not preserved."
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

    private func decodeNullSeparatedArguments(from data: Data) -> [String] {
        var args = data
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        while args.last == "" {
            args.removeLast()
        }
        return args
    }
}

private extension AppConfig {
    func withProvider(
        _ provider: CLIProvider,
        executablePath: String,
        model: String? = nil,
        timeoutSeconds: Int? = nil
    ) -> AppConfig {
        var claudePath = claudePath
        var codexPath = codexPath
        var geminiPath = geminiPath

        switch provider {
        case .claude:
            claudePath = executablePath
        case .codex:
            codexPath = executablePath
        case .gemini:
            geminiPath = executablePath
        }

        return AppConfig(
            claudePath: claudePath,
            codexPath: codexPath,
            geminiPath: geminiPath,
            provider: provider.rawValue,
            model: model ?? AppConfig.defaultModel(for: provider),
            timeoutSeconds: timeoutSeconds ?? self.timeoutSeconds,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            launchAtLogin: launchAtLogin,
            historyLimit: historyLimit
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
