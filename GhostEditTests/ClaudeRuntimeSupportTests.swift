import XCTest
@testable import GhostEditCore

final class ClaudeRuntimeSupportTests: XCTestCase {
    func testClaudeSearchPathsIncludesDefaultsAndDeduplicates() {
        let paths = ClaudeRuntimeSupport.claudeSearchPaths(
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
            exitCode: 1,
            stdout: "",
            stderr: "API ERROR: 401 authentication_error: OAuth token has expired"
        )

        guard case ShellRunnerError.authenticationRequired = error else {
            return XCTFail("Expected authenticationRequired, got: \(error)")
        }
    }

    func testClassifyProcessFailurePrefersStderrWhenPresent() {
        let error = ClaudeRuntimeSupport.classifyProcessFailure(
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

    func testClaudeArgumentsIncludesModelWhenProvided() {
        let args = ClaudeRuntimeSupport.claudeArguments(prompt: "prompt", model: "haiku")

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

    func testClaudeArgumentsOmitsModelWhenBlank() {
        let args = ClaudeRuntimeSupport.claudeArguments(prompt: "prompt", model: "   ")

        XCTAssertEqual(args, [
            "-p",
            "prompt",
            "--setting-sources",
            "user",
            "--tools",
            ""
        ])
    }
}
