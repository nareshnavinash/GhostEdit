import XCTest
@testable import GhostEditCore

final class ClaudeRuntimeSupportTests: XCTestCase {
    func testCLISearchPathsIncludesDefaultsAndDeduplicates() {
        let paths = ClaudeRuntimeSupport.cliSearchPaths(
            provider: .claude,
            homeDirectoryPath: "/Users/example",
            environment: ["PATH": "/usr/local/bin:/custom/bin:/usr/local/bin"]
        )

        XCTAssertEqual(paths, [
            "/Users/example/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
            "/Users/example/bin/claude",
            "/custom/bin/claude"
        ])
    }

    func testCLISearchPathsUsesProviderExecutableName() {
        let codexPaths = ClaudeRuntimeSupport.cliSearchPaths(
            provider: .codex,
            homeDirectoryPath: "/Users/example",
            environment: ["PATH": "/custom/bin"]
        )
        let geminiPaths = ClaudeRuntimeSupport.cliSearchPaths(
            provider: .gemini,
            homeDirectoryPath: "/Users/example",
            environment: ["PATH": "/custom/bin"]
        )

        XCTAssertTrue(codexPaths.contains("/custom/bin/codex"))
        XCTAssertTrue(geminiPaths.contains("/custom/bin/gemini"))
    }

    func testRuntimePathValuePreservesOrderAndDeduplicates() {
        let pathValue = ClaudeRuntimeSupport.runtimePathValue(
            homeDirectoryPath: "/Users/example",
            environment: ["PATH": "/custom/bin:/usr/bin:/custom/bin"]
        )

        XCTAssertEqual(pathValue, [
            "/custom/bin",
            "/usr/bin",
            "/Users/example/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":"))
    }

    func testClassifyProcessFailureDetectsAuthenticationFromCombinedOutput() {
        let error = ClaudeRuntimeSupport.classifyProcessFailure(
            provider: .claude,
            exitCode: 1,
            stdout: "",
            stderr: "API ERROR: 401 authentication_error: OAuth token has expired"
        )

        guard case let ShellRunnerError.authenticationRequired(provider) = error else {
            return XCTFail("Expected authenticationRequired, got: \(error)")
        }
        XCTAssertEqual(provider, .claude)
    }

    func testClassifyProcessFailureDetectsAuthenticationFromProviderLoginHint() {
        let error = ClaudeRuntimeSupport.classifyProcessFailure(
            provider: .codex,
            exitCode: 2,
            stdout: "please run codex login",
            stderr: ""
        )

        guard case let ShellRunnerError.authenticationRequired(provider) = error else {
            return XCTFail("Expected authenticationRequired, got: \(error)")
        }
        XCTAssertEqual(provider, .codex)
    }

    func testClassifyProcessFailurePrefersStderrWhenPresent() {
        let error = ClaudeRuntimeSupport.classifyProcessFailure(
            provider: .gemini,
            exitCode: 9,
            stdout: "stdout message",
            stderr: "stderr message"
        )

        guard case let ShellRunnerError.processFailed(exitCode, stderr) = error else {
            return XCTFail("Expected processFailed, got: \(error)")
        }

        XCTAssertEqual(exitCode, 9)
        XCTAssertEqual(stderr, "stderr message")
    }

    func testClassifyProcessFailureFallsBackToStdoutWhenStderrMissing() {
        let error = ClaudeRuntimeSupport.classifyProcessFailure(
            provider: .gemini,
            exitCode: 7,
            stdout: "stdout details",
            stderr: "\n   \n"
        )

        guard case let ShellRunnerError.processFailed(exitCode, stderr) = error else {
            return XCTFail("Expected processFailed, got: \(error)")
        }

        XCTAssertEqual(exitCode, 7)
        XCTAssertEqual(stderr, "stdout details")
    }

    func testCLIArgumentsForClaudeIncludesModelWhenProvided() {
        let args = ClaudeRuntimeSupport.cliArguments(
            provider: .claude,
            prompt: "prompt",
            model: "haiku"
        )

        XCTAssertEqual(args, [
            "-p",
            "prompt",
            "--setting-sources",
            "user",
            "--tools",
            "",
            "--model",
            "haiku"
        ])
    }

    func testCLIArgumentsForClaudeOmitsModelWhenBlank() {
        let args = ClaudeRuntimeSupport.cliArguments(
            provider: .claude,
            prompt: "prompt",
            model: "   "
        )

        XCTAssertEqual(args, [
            "-p",
            "prompt",
            "--setting-sources",
            "user",
            "--tools",
            ""
        ])
    }

    func testCLIArgumentsForCodex() {
        let withModel = ClaudeRuntimeSupport.cliArguments(
            provider: .codex,
            prompt: "hello",
            model: "gpt-5-codex"
        )
        let withoutModel = ClaudeRuntimeSupport.cliArguments(
            provider: .codex,
            prompt: "hello",
            model: "   "
        )

        XCTAssertEqual(withModel, [
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "-c",
            "model_reasoning_effort='low'",
            "--model",
            "gpt-5-codex",
            "hello"
        ])
        XCTAssertEqual(withoutModel, [
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "-c",
            "model_reasoning_effort='low'",
            "hello"
        ])
    }

    func testCLIArgumentsForGemini() {
        let withModel = ClaudeRuntimeSupport.cliArguments(
            provider: .gemini,
            prompt: "hello",
            model: "gemini-2.5-flash"
        )
        let withoutModel = ClaudeRuntimeSupport.cliArguments(
            provider: .gemini,
            prompt: "hello",
            model: ""
        )

        XCTAssertEqual(withModel, [
            "--prompt",
            "hello",
            "--output-format",
            "text",
            "--model",
            "gemini-2.5-flash"
        ])
        XCTAssertEqual(withoutModel, [
            "--prompt",
            "hello",
            "--output-format",
            "text"
        ])
    }

    func testClaudeWrapperFunctionsMapToGenericHelpers() {
        let searchPaths = ClaudeRuntimeSupport.claudeSearchPaths(
            homeDirectoryPath: "/Users/example",
            environment: ["PATH": "/custom/bin"]
        )
        let args = ClaudeRuntimeSupport.claudeArguments(prompt: "p", model: "haiku")

        XCTAssertTrue(searchPaths.contains("/custom/bin/claude"))
        XCTAssertEqual(args, [
            "-p",
            "p",
            "--setting-sources",
            "user",
            "--tools",
            "",
            "--model",
            "haiku"
        ])
    }
}
