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
            return "The claude CLI could not be found. Set an absolute path in ~/.grammarfixer/config.json."
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
    private let fileManager = FileManager.default
    private let shellSession = PersistentShellSession()

    private let discoveredPathLock = NSLock()
    private var discoveredClaudePath: String?
    private let sessionLock = NSLock()
    private var preferSession = false

    init(configManager: ConfigManager) {
        self.configManager = configManager
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

    private func resolveClaudePath(preferredPath: String?) throws -> String {
        if let preferredPath, isExecutable(preferredPath) {
            return preferredPath
        }

        discoveredPathLock.lock()
        if let cached = discoveredClaudePath, isExecutable(cached) {
            discoveredPathLock.unlock()
            return cached
        }
        discoveredPathLock.unlock()

        for path in claudeSearchPaths() where isExecutable(path) {
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

    private func claudeSearchPaths() -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        func appendUnique(_ path: String) {
            guard !path.isEmpty else { return }
            let expanded = NSString(string: path).expandingTildeInPath
            guard !expanded.isEmpty, !seen.contains(expanded) else {
                return
            }
            seen.insert(expanded)
            paths.append(expanded)
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        appendUnique("\(home)/.local/bin/claude")
        appendUnique("/opt/homebrew/bin/claude")
        appendUnique("/usr/local/bin/claude")
        appendUnique("/usr/bin/claude")
        appendUnique("\(home)/bin/claude")

        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for directory in envPath.split(separator: ":") {
                appendUnique("\(directory)/claude")
            }
        }

        return paths
    }

    private func runtimePathValue() -> String {
        var components: [String] = []
        var seen = Set<String>()

        func appendUnique(_ value: String) {
            guard !value.isEmpty, !seen.contains(value) else { return }
            seen.insert(value)
            components.append(value)
        }

        if let existingPath = ProcessInfo.processInfo.environment["PATH"] {
            for path in existingPath.split(separator: ":") {
                appendUnique(String(path))
            }
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        appendUnique("\(home)/.local/bin")
        appendUnique("/opt/homebrew/bin")
        appendUnique("/usr/local/bin")
        appendUnique("/usr/bin")
        appendUnique("/bin")
        appendUnique("/usr/sbin")
        appendUnique("/sbin")

        return components.joined(separator: ":")
    }

    private func classifyProcessFailure(
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> ShellRunnerError {
        let combined = "\(stdout)\n\(stderr)".lowercased()
        let normalized = combined
        if normalized.contains("failed to authenticate")
            || normalized.contains("authentication_error")
            || normalized.contains("token has expired")
            || normalized.contains("oauth token")
            || normalized.contains("claude auth login")
            || normalized.contains("api error: 401")
            || normalized.contains("unauthorized")
        {
            return .authenticationRequired
        }

        let preferredDetails = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? stdout
            : stderr
        return .processFailed(exitCode: exitCode, stderr: preferredDetails)
    }

    private func claudeArguments(prompt: String, model: String) -> [String] {
        var args = [
            "-p",
            prompt,
            // Avoid project/local config side effects while keeping user auth/settings.
            "--setting-sources",
            "user",
            // GrammarFixer only needs text generation, not tool/file access.
            "--tools",
            ""
        ]

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--model", trimmedModel])
        }

        return args
    }

    private func runClaude(
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            return try runClaudePreferredPath(
                executablePath: executablePath,
                model: trimmedModel,
                prompt: prompt,
                timeoutSeconds: timeoutSeconds
            )
        } catch let error as ShellRunnerError {
            // Some CLI versions reject aliases like "haiku". Retry once with default model.
            if case .processFailed = error, !trimmedModel.isEmpty {
                return try runClaudePreferredPath(
                    executablePath: executablePath,
                    model: "",
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds
                )
            }
            throw error
        }
    }

    private func runClaudePreferredPath(
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        if shouldUseSession() {
            do {
                return try runClaudeViaShellSession(
                    executablePath: executablePath,
                    model: model,
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds
                )
            } catch {
                // Session path is opportunistic for latency. If it fails, disable and fallback.
                shellSession.markUnhealthy()
                setPreferSession(false)
            }
        }

        return try runClaudeDirect(
            executablePath: executablePath,
            model: model,
            prompt: prompt,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runClaudeViaShellSession(
        executablePath: String,
        model: String,
        prompt: String,
        timeoutSeconds: Int
    ) throws -> String {
        let args = claudeArguments(prompt: prompt, model: model)

        let pathValue = runtimePathValue()

        let command = "PATH=\(shellQuote(pathValue)); export PATH; \(shellQuote(executablePath)) \(args.map(shellQuote).joined(separator: " "))"
        let result = try shellSession.run(command: command, timeoutSeconds: timeoutSeconds)

        guard result.exitCode == 0 else {
            throw classifyProcessFailure(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr
            )
        }

        return result.stdout
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
        process.arguments = claudeArguments(prompt: prompt, model: model)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = runtimePathValue()
        process.environment = environment

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
            throw classifyProcessFailure(
                exitCode: process.terminationStatus,
                stdout: outputText,
                stderr: errorText
            )
        }

        return outputText
    }

    private func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func shouldUseSession() -> Bool {
        sessionLock.lock()
        let current = preferSession
        sessionLock.unlock()
        return current && shellSession.healthy()
    }

    private func setPreferSession(_ value: Bool) {
        sessionLock.lock()
        preferSession = value
        sessionLock.unlock()
    }
}
