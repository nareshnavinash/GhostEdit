import Foundation

enum ShellRunnerError: LocalizedError {
    case claudeNotFound
    case launchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "The claude CLI could not be found. Set an absolute path in ~/.grammarfixer/config.json."
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
    private var preferSession = true

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func prewarm() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let config = self.configManager.loadConfig()
            _ = try? self.resolveClaudePath(preferredPath: config.resolvedClaudePath)
            do {
                try self.shellSession.prewarm()
                self.setPreferSession(true)
            } catch {
                self.shellSession.markUnhealthy()
                self.setPreferSession(false)
            }
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

        let standardPaths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        for path in standardPaths where isExecutable(path) {
            cacheDiscoveredPath(path)
            return path
        }

        if let zshPath = lookupClaudeViaShell(shellPath: "/bin/zsh") {
            cacheDiscoveredPath(zshPath)
            return zshPath
        }

        if let bashPath = lookupClaudeViaShell(shellPath: "/bin/bash") {
            cacheDiscoveredPath(bashPath)
            return bashPath
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

    private func lookupClaudeViaShell(shellPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", "command -v claude"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let rawPath = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawPath.isEmpty,
            isExecutable(rawPath)
        else {
            return nil
        }

        return rawPath
    }

    private func runClaude(
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
        var args = ["-p", prompt]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--model", trimmedModel])
        }

        let pathValue = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        let command = "PATH=\(shellQuote(pathValue)); export PATH; \(shellQuote(executablePath)) \(args.map(shellQuote).joined(separator: " "))"
        let result = try shellSession.run(command: command, timeoutSeconds: timeoutSeconds)

        guard result.exitCode == 0 else {
            throw ShellRunnerError.processFailed(
                exitCode: result.exitCode,
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

        var args = ["-p", prompt]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--model", trimmedModel])
        }
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
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
            throw ShellRunnerError.processFailed(
                exitCode: process.terminationStatus,
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
