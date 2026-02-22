import Foundation

final class PersistentShellSession {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private let serialQueue = DispatchQueue(label: "com.ghostedit.shell-session")
    private let outputCondition = NSCondition()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var outputBuffer = Data()
    private var isHealthy = false

    deinit {
        serialQueue.sync {
            teardownLocked()
        }
    }

    func prewarm() throws {
        try serialQueue.sync {
            try ensureRunningLocked()
            // Quick health check. If this fails, caller can fallback to direct execution.
            let pingToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let pingCommand = "printf '__GF_PING_\(pingToken)__\\n'; printf '__GF_EXIT_\(pingToken)__:%d\\n' 0"
            try writeLineLocked(pingCommand)
            _ = try waitForExitMarkerLocked(token: pingToken, timeoutSeconds: 3)
            isHealthy = true
        }
    }

    func markUnhealthy() {
        serialQueue.sync {
            isHealthy = false
            teardownLocked()
        }
    }

    func healthy() -> Bool {
        serialQueue.sync { isHealthy }
    }

    func run(command: String, timeoutSeconds: Int) throws -> Result {
        try serialQueue.sync {
            try ensureRunningLocked()

            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let stdoutURL = makeTempFileURL(token: token, suffix: "stdout")
            let stderrURL = makeTempFileURL(token: token, suffix: "stderr")

            let wrappedCommand = "\(command) > \(shellQuote(stdoutURL.path)) 2> \(shellQuote(stderrURL.path)); printf '__GF_EXIT_\(token)__:%d\\n' $?"

            do {
                try writeLineLocked(wrappedCommand)
                let exitCode = try waitForExitMarkerLocked(token: token, timeoutSeconds: timeoutSeconds + 2)

                let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
                let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)

                return Result(exitCode: exitCode, stdout: stdoutText, stderr: stderrText)
            } catch {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
                teardownLocked()
                throw error
            }
        }
    }

    private func ensureRunningLocked() throws {
        if let process, process.isRunning {
            return
        }

        teardownLocked()

        // Use zsh explicitly because command quoting in this class is POSIX/zsh-style.
        let shellPath = "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        // Login shell loads user profile paths; non-interactive avoids prompt/plugin side effects.
        process.arguments = ["-l"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw ShellRunnerError.launchFailed("Could not start shell session: \(error.localizedDescription)")
        }

        self.process = process
        self.stdinHandle = inputPipe.fileHandleForWriting
        self.stdoutHandle = outputPipe.fileHandleForReading

        outputBuffer.removeAll(keepingCapacity: false)

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            self.outputCondition.lock()
            self.outputBuffer.append(data)
            self.outputCondition.signal()
            self.outputCondition.unlock()
        }
        isHealthy = true
    }

    private func teardownLocked() {
        stdoutHandle?.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        try? stdinHandle?.close()
        try? stdoutHandle?.close()

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        isHealthy = false

        outputCondition.lock()
        outputBuffer.removeAll(keepingCapacity: false)
        outputCondition.unlock()
    }

    private func writeLineLocked(_ line: String) throws {
        guard let stdinHandle else {
            throw ShellRunnerError.launchFailed("Shell session is not available.")
        }

        guard let data = (line + "\n").data(using: .utf8) else {
            throw ShellRunnerError.launchFailed("Could not encode shell command.")
        }

        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw ShellRunnerError.launchFailed("Could not write to shell session: \(error.localizedDescription)")
        }
    }

    private func waitForExitMarkerLocked(token: String, timeoutSeconds: Int) throws -> Int32 {
        let markerPrefix = "__GF_EXIT_\(token)__:"
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while true {
            outputCondition.lock()
            if let exitCode = extractExitCodeIfAvailableLocked(markerPrefix: markerPrefix) {
                outputCondition.unlock()
                return exitCode
            }

            if Date() >= deadline {
                outputCondition.unlock()
                throw ShellRunnerError.timedOut(seconds: timeoutSeconds)
            }

            let waitUntil = Date().addingTimeInterval(0.15)
            outputCondition.wait(until: waitUntil)
            outputCondition.unlock()
        }
    }

    private func extractExitCodeIfAvailableLocked(markerPrefix: String) -> Int32? {
        let text = String(decoding: outputBuffer, as: UTF8.self)
        guard let markerRange = text.range(of: markerPrefix) else {
            return nil
        }

        guard let lineEnd = text[markerRange.upperBound...].firstIndex(of: "\n") else {
            return nil
        }

        let codeSlice = text[markerRange.upperBound..<lineEnd]
        let code = Int32(codeSlice.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1

        let consumedText = text[..<text.index(after: lineEnd)]
        let consumedBytes = consumedText.utf8.count
        if consumedBytes <= outputBuffer.count {
            outputBuffer.removeFirst(consumedBytes)
        } else {
            outputBuffer.removeAll(keepingCapacity: false)
        }

        return code
    }

    private func makeTempFileURL(token: String, suffix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ghostedit-\(token)-\(suffix).txt")
    }

    private func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
