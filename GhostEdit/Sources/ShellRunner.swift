import Foundation

enum ShellRunnerError: LocalizedError {
    case claudeNotFound
    case authenticationRequired
    case launchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "The claude CLI could not be found. Set an absolute path in ~/.ghostedit/config.json."
        case .authenticationRequired:
            return "Claude authentication has expired. Run `claude auth login` in Terminal, then try again."
        case let .launchFailed(message):
            return "Failed to start claude: \(message)"
        case let .processFailed(exitCode, stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return details.isEmpty
                ? "claude exited with code \(exitCode)."
                : "claude exited with code \(exitCode): \(details)"
        case let .timedOut(seconds):
            return "claude timed out after \(seconds) seconds."
        case .emptyResponse:
            return "claude returned an empty response."
        }
    }
}

final class ShellRunner {
    private let configManager: ConfigManager
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectoryPath: String

    private let discoveredPathLock = NSLock()
    private var discoveredClaudePath: String?

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
            _ = try? self.resolveClaudePath(preferredPath: config.resolvedClaudePath)
        }
    }

    func correctText(systemPrompt: String, selectedText: String) throws -> String {
        let config = configManager.loadConfig()
        let claudePath = try resolveClaudePath(preferredPath: config.resolvedClaudePath)
        let model = config.resolvedModel
        let input = "\(systemPrompt)\n\n\(selectedText)"

        let output = try runClaude(
            executablePath: claudePath,
            model: model,
            prompt: input,
            timeoutSeconds: config.timeoutSeconds
        )

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShellRunnerError.emptyResponse
        }

        return trimmed
    }

    func resolveClaudePath(preferredPath: String?) throws -> String {
        if let preferredPath, isExecutable(preferredPath) {
            return preferredPath
        }

        discoveredPathLock.lock()
        if let cached = discoveredClaudePath, isExecutable(cached) {
            discoveredPathLock.unlock()
            return cached
        }
        discoveredPathLock.unlock()

        let searchPaths = ClaudeRuntimeSupport.claudeSearchPaths(
            homeDirectoryPath: homeDirectoryPath,
            environment: environment
        )

        for path in searchPaths where isExecutable(path) {
            cacheDiscoveredPath(path)
            return path
        }

        throw ShellRunnerError.claudeNotFound
    }

    private func cacheDiscoveredPath(_ path: String) {
        discoveredPathLock.lock()
        discoveredClaudePath = path
        discoveredPathLock.unlock()
    }

    private func isExecutable(_ path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    private func runClaude(
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            return try runClaudeDirect(
                executablePath: executablePath,
                model: trimmedModel,
                prompt: prompt,
                timeoutSeconds: timeoutSeconds
            )
        } catch let error as ShellRunnerError {
            // Some CLI versions reject aliases like "haiku". Retry once with default model.
            if case .processFailed = error, !trimmedModel.isEmpty {
                return try runClaudeDirect(
                    executablePath: executablePath,
                    model: "",
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds
                )
            }
            throw error
        }
    }

    private func runClaudeDirect(
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = configManager.baseDirectoryURL
        process.arguments = ClaudeRuntimeSupport.claudeArguments(prompt: prompt, model: model)

        var runtimeEnvironment = environment
        runtimeEnvironment["PATH"] = ClaudeRuntimeSupport.runtimePathValue(
            homeDirectoryPath: homeDirectoryPath,
            environment: environment
        )
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
            throw ShellRunnerError.launchFailed(error.localizedDescription)
        }

        if completion.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + .seconds(2))
            throw ShellRunnerError.timedOut(seconds: timeoutSeconds)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ClaudeRuntimeSupport.classifyProcessFailure(
                exitCode: process.terminationStatus,
                stdout: outputText,
                stderr: errorText
            )
        }

        return outputText
    }

}
