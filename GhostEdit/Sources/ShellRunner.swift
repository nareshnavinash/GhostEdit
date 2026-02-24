import Foundation

enum ShellRunnerError: LocalizedError {
    case cliNotFound(provider: CLIProvider)
    case authenticationRequired(provider: CLIProvider)
    case launchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Int)
    case emptyResponse
    case protectedTokensModified

    var errorDescription: String? {
        switch self {
        case let .cliNotFound(provider):
            return "The \(provider.executableName) CLI could not be found. Set an absolute path in ~/.ghostedit/config.json or switch provider in Settings."
        case let .authenticationRequired(provider):
            return "\(provider.displayName) authentication has expired. Run `\(provider.authCommand)` in Terminal, then try again."
        case let .launchFailed(message):
            return "Failed to start CLI process: \(message)"
        case let .processFailed(exitCode, stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return details.isEmpty
                ? "CLI exited with code \(exitCode). Try switching the model in Settings if the selected model is busy."
                : "CLI exited with code \(exitCode): \(details)\nTry switching the model in Settings if this model is busy or unavailable."
        case let .timedOut(seconds):
            return "CLI timed out after \(seconds) seconds. Try switching the model in Settings if the selected model is busy."
        case .emptyResponse:
            return "CLI returned an empty response. Try switching the model in Settings."
        case .protectedTokensModified:
            return "The AI response changed protected static tokens. Retried once, but placeholders were not preserved."
        }
    }
}

final class ShellRunner {
    private let configManager: ConfigManager
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectoryPath: String
    weak var developerModeLogger: DeveloperModeLogger?

    private let discoveredPathLock = NSLock()
    private var discoveredCLIPaths: [CLIProvider: String] = [:]

    init(
        configManager: ConfigManager,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryPath: String? = nil
    ) {
        self.configManager = configManager
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectoryPath = homeDirectoryPath ?? fileManager.homeDirectoryForCurrentUser.path
    }

    func prewarm() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let config = self.configManager.loadConfig()
            let provider = config.resolvedProvider
            _ = try? self.resolveCLIPath(
                provider: provider,
                preferredPath: config.resolvedPath(for: provider)
            )
        }
    }

    func correctText(systemPrompt: String, selectedText: String) throws -> String {
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        devLog(.cliResolution, "Resolving CLI path for provider: \(provider.displayName)")
        let executablePath = try resolveCLIPath(
            provider: provider,
            preferredPath: config.resolvedPath(for: provider)
        )
        devLog(.cliResolution, "Resolved CLI path: \(executablePath)")
        let model = config.resolvedModel(for: provider)

        var augmentedPrompt = systemPrompt
        if let langInstruction = AppConfig.languageInstruction(for: config.resolvedLanguage) {
            augmentedPrompt = "\(systemPrompt) \(langInstruction)"
            devLog(.cliExecution, "Language: \(config.resolvedLanguage) → \(langInstruction)")
        }
        let input = "\(augmentedPrompt)\n\n\(selectedText)"

        devLog(.cliExecution, "Launching \(provider.executableName) with model: \(model.isEmpty ? "(default)" : model), timeout: \(config.timeoutSeconds)s")
        let output = try runCLI(
            provider: provider,
            executablePath: executablePath,
            model: model,
            prompt: input,
            timeoutSeconds: config.timeoutSeconds
        )

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            devLog(.cliResponse, "CLI returned empty response")
            throw ShellRunnerError.emptyResponse
        }

        devLog(.cliResponse, "CLI response (\(trimmed.count) chars): \(DeveloperModeSupport.truncate(trimmed))")
        return trimmed
    }

    func correctTextPreservingTokens(
        systemPrompt: String,
        selectedText: String,
        maxValidationRetries: Int = 1
    ) throws -> String {
        let protection = TokenPreservationSupport.protectTokens(in: selectedText)
        guard protection.hasProtectedTokens else {
            devLog(.tokenProtection, "No protected tokens found, using direct correction")
            return try correctText(systemPrompt: systemPrompt, selectedText: selectedText)
        }

        devLog(.tokenProtection, "Protected \(protection.tokens.count) token(s): \(protection.tokens.map { "\($0.placeholder)=\(DeveloperModeSupport.truncate($0.originalToken, maxLength: 40))" }.joined(separator: ", "))")
        let augmentedPrompt = TokenPreservationSupport.appendInstruction(to: systemPrompt)
        let retries = max(0, maxValidationRetries)
        var lastCandidate = ""

        for attempt in 0...retries {
            devLog(.cliExecution, "Token-preserving correction attempt \(attempt + 1)/\(retries + 1)")
            lastCandidate = try correctText(
                systemPrompt: augmentedPrompt,
                selectedText: protection.protectedText
            )

            if TokenPreservationSupport.placeholdersAreIntact(in: lastCandidate, tokens: protection.tokens) {
                devLog(.tokenRestoration, "All placeholders intact, restoring tokens")
                return TokenPreservationSupport.restoreTokens(in: lastCandidate, tokens: protection.tokens)
            }
            devLog(.tokenRestoration, "Placeholders modified by AI on attempt \(attempt + 1)")
        }

        // Placeholders were modified by the AI — retry with the original text
        // and an explicit instruction to preserve emoji codes and other tokens.
        devLog(.tokenRestoration, "Retrying with original text and token-aware instruction")
        let segments = TokenPreservationSupport.splitAroundTokens(in: selectedText)
        let tokenAwarePrompt = TokenPreservationSupport.appendTokenAwareInstruction(to: systemPrompt)

        let retryWithOriginal = try correctText(
            systemPrompt: tokenAwarePrompt,
            selectedText: selectedText
        )

        // If all original tokens survived in the retry, return it directly.
        if segments.tokens.allSatisfy({ retryWithOriginal.contains($0) }) {
            devLog(.tokenRestoration, "Token-aware retry preserved all tokens")
            return retryWithOriginal
        }

        // Last resort: best-effort restoration on the placeholder-based attempt.
        devLog(.tokenRestoration, "Falling back to best-effort token restoration")
        return TokenPreservationSupport.bestEffortRestore(in: lastCandidate, tokens: protection.tokens)
    }

    func resolveCLIPath(provider: CLIProvider, preferredPath: String?) throws -> String {
        if let preferredPath, isExecutable(preferredPath) {
            return preferredPath
        }

        discoveredPathLock.lock()
        if let cached = discoveredCLIPaths[provider], isExecutable(cached) {
            discoveredPathLock.unlock()
            return cached
        }
        discoveredPathLock.unlock()

        let searchPaths = ClaudeRuntimeSupport.cliSearchPaths(
            provider: provider,
            homeDirectoryPath: homeDirectoryPath,
            environment: environment
        )

        for path in searchPaths where isExecutable(path) {
            cacheDiscoveredPath(path, provider: provider)
            return path
        }

        throw ShellRunnerError.cliNotFound(provider: provider)
    }

    func resolveClaudePath(preferredPath: String?) throws -> String {
        try resolveCLIPath(provider: .claude, preferredPath: preferredPath)
    }

    private func cacheDiscoveredPath(_ path: String, provider: CLIProvider) {
        discoveredPathLock.lock()
        discoveredCLIPaths[provider] = path
        discoveredPathLock.unlock()
    }

    private func isExecutable(_ path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    private func runCLI(
        provider: CLIProvider,
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            return try runCLIDirect(
                provider: provider,
                executablePath: executablePath,
                model: trimmedModel,
                prompt: prompt,
                timeoutSeconds: timeoutSeconds
            )
        } catch let error as ShellRunnerError {
            // Some CLI versions reject aliases like "haiku". Retry once with default model.
            if case .processFailed = error, !trimmedModel.isEmpty {
                devLog(.cliExecution, "CLI failed with model '\(trimmedModel)', retrying without model flag")
                return try runCLIDirect(
                    provider: provider,
                    executablePath: executablePath,
                    model: "",
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds
                )
            }
            throw error
        }
    }

    private func runCLIDirect(
        provider: CLIProvider,
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = configManager.baseDirectoryURL
        let args = ClaudeRuntimeSupport.cliArguments(
            provider: provider,
            prompt: prompt,
            model: model
        )
        process.arguments = args

        devLog(.cliExecution, "$ \(executablePath) \(args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))")

        var runtimeEnvironment = environment
        runtimeEnvironment["PATH"] = ClaudeRuntimeSupport.runtimePathValue(
            homeDirectoryPath: homeDirectoryPath,
            environment: environment
        )
        // Remove CLAUDECODE env var to prevent "nested session" errors when
        // GhostEdit is launched from within a Claude Code terminal session.
        runtimeEnvironment.removeValue(forKey: "CLAUDE_CODE")
        runtimeEnvironment.removeValue(forKey: "CLAUDECODE")
        process.environment = runtimeEnvironment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        do {
            try process.run()
        } catch {
            devLog(.cliExecution, "Failed to launch process: \(error.localizedDescription)")
            throw ShellRunnerError.launchFailed(error.localizedDescription)
        }

        if completion.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + .seconds(2))
            devLog(.cliExecution, "Process timed out after \(timeoutSeconds)s")
            throw ShellRunnerError.timedOut(seconds: timeoutSeconds)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        devLog(.cliExecution, "Process exited with code \(process.terminationStatus)")
        if !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            devLog(.cliExecution, "stderr: \(DeveloperModeSupport.truncate(errorText))")
        }

        guard process.terminationStatus == 0 else {
            throw ClaudeRuntimeSupport.classifyProcessFailure(
                provider: provider,
                exitCode: process.terminationStatus,
                stdout: outputText,
                stderr: errorText
            )
        }

        return outputText
    }

    private func devLog(_ phase: DeveloperModeLogEntry.Phase, _ message: String) {
        developerModeLogger?.log(DeveloperModeLogEntry(phase: phase, message: message))
    }
}
