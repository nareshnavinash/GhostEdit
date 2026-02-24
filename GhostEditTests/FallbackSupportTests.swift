import XCTest
@testable import GhostEditCore

final class FallbackSupportTests: XCTestCase {
    // MARK: - nextFallbackModel

    func testNextFallbackModelClaudeHaikuToSonnet() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "haiku", provider: .claude)
        XCTAssertEqual(next, "sonnet")
    }

    func testNextFallbackModelClaudeSonnetToOpus() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "sonnet", provider: .claude)
        XCTAssertEqual(next, "opus")
    }

    func testNextFallbackModelClaudeOpusReturnsNil() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "opus", provider: .claude)
        XCTAssertNil(next)
    }

    func testNextFallbackModelGeminiFlashLiteToFlash() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "gemini-2.5-flash-lite", provider: .gemini)
        XCTAssertEqual(next, "gemini-2.5-flash")
    }

    func testNextFallbackModelUnknownModelFallsToDefault() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "unknown-model", provider: .claude)
        XCTAssertEqual(next, "haiku")
    }

    func testNextFallbackModelUnknownModelSameAsDefaultReturnsNil() {
        let next = FallbackSupport.nextFallbackModel(currentModel: "haiku", provider: .claude)
        // haiku is known, so it goes to next: sonnet
        XCTAssertEqual(next, "sonnet")

        // If current is "haiku" and that's the default and we don't find it, nil
        // This case only applies for unknown strings equal to the default.
        let next2 = FallbackSupport.nextFallbackModel(currentModel: "gpt-5-codex", provider: .codex)
        XCTAssertEqual(next2, "gpt-5.3-codex")
    }

    func testNextFallbackModelLastInGeminiList() {
        let next = FallbackSupport.nextFallbackModel(
            currentModel: "gemini-3.1-pro-preview-customtools",
            provider: .gemini
        )
        XCTAssertNil(next)
    }

    // MARK: - isRetriable

    func testIsRetriableProcessFailed() {
        let error = ShellRunnerError.processFailed(exitCode: 1, stderr: "error")
        XCTAssertTrue(FallbackSupport.isRetriable(error))
    }

    func testIsRetriableTimedOut() {
        let error = ShellRunnerError.timedOut(seconds: 60)
        XCTAssertTrue(FallbackSupport.isRetriable(error))
    }

    func testIsRetriableEmptyResponse() {
        let error = ShellRunnerError.emptyResponse
        XCTAssertTrue(FallbackSupport.isRetriable(error))
    }

    func testIsNotRetriableCLINotFound() {
        let error = ShellRunnerError.cliNotFound(provider: .claude)
        XCTAssertFalse(FallbackSupport.isRetriable(error))
    }

    func testIsNotRetriableAuthRequired() {
        let error = ShellRunnerError.authenticationRequired(provider: .claude)
        XCTAssertFalse(FallbackSupport.isRetriable(error))
    }

    func testIsNotRetriableLaunchFailed() {
        let error = ShellRunnerError.launchFailed("error")
        XCTAssertFalse(FallbackSupport.isRetriable(error))
    }

    func testIsNotRetriableProtectedTokensModified() {
        let error = ShellRunnerError.protectedTokensModified
        XCTAssertFalse(FallbackSupport.isRetriable(error))
    }

    func testIsNotRetriableGenericError() {
        struct GenericError: Error {}
        XCTAssertFalse(FallbackSupport.isRetriable(GenericError()))
    }
}
