import Foundation

enum FallbackSupport {
    /// Returns the next model to try for a given provider after the current
    /// model fails. Returns `nil` when no fallback is available.
    static func nextFallbackModel(
        currentModel: String,
        provider: CLIProvider
    ) -> String? {
        let models = provider.availableModels
        guard let idx = models.firstIndex(of: currentModel) else {
            // Unknown model — try the default as fallback.
            let defaultModel = provider.defaultModel
            return currentModel == defaultModel ? nil : defaultModel
        }
        // Try the next model in the list (wrapping is intentionally NOT done —
        // only one fallback attempt per correction).
        let nextIdx = idx + 1
        guard nextIdx < models.count else {
            return nil
        }
        return models[nextIdx]
    }

    /// Determines whether the given error is retriable with a different model.
    static func isRetriable(_ error: Error) -> Bool {
        guard let shellError = error as? ShellRunnerError else {
            return false
        }
        switch shellError {
        case .processFailed, .timedOut, .emptyResponse:
            return true
        case .cliNotFound, .authenticationRequired, .launchFailed, .protectedTokensModified:
            return false
        }
    }
}
