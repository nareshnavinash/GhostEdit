import Foundation

/// Protocol that ShellRunner uses to talk to a persistent CLI session.
/// Extracted so tests can inject a mock without spawning a real process.
protocol PersistentCLISessionProtocol: AnyObject {
    var isReady: Bool { get }
    func spawn(executablePath: String, provider: CLIProvider, model: String, systemPrompt: String, environment: [String: String], workingDirectoryURL: URL?) throws
    func send(prompt: String, timeoutSeconds: Int) throws -> PersistentCLISession.StreamResult
    func sendStreaming(prompt: String, timeoutSeconds: Int, onChunk: @escaping (String) -> Void) throws -> PersistentCLISession.StreamResult
    func kill()
}

/// Keeps a single CLI process (claude, codex, or gemini) alive in stream-json
/// mode so that successive corrections skip the bootstrap + TLS overhead.
///
/// Lifecycle managed by ShellRunner:
///   1. `spawn()` at app launch (or after each correction finishes)
///   2. `send()` when Cmd+E fires — writes a user message to the warm process
///   3. After the result arrives the caller spawns a fresh session immediately
///
/// Only the Claude provider supports stream-json today; for other providers
/// the caller should fall back to the one-shot `runCLIDirect` path.
final class PersistentCLISession: PersistentCLISessionProtocol {

    // MARK: - Types

    struct StreamResult {
        let text: String
    }

    enum SessionError: LocalizedError {
        case notReady
        case processExited(code: Int32)
        case timedOut(seconds: Int)
        case emptyResponse
        case malformedResponse(detail: String)
        case spawnFailed(String)

        var errorDescription: String? {
            switch self {
            case .notReady:
                return "Persistent CLI session is not ready."
            case let .processExited(code):
                return "CLI process exited unexpectedly with code \(code)."
            case let .timedOut(seconds):
                return "CLI session timed out after \(seconds) seconds."
            case .emptyResponse:
                return "CLI session returned an empty response."
            case let .malformedResponse(detail):
                return "Malformed CLI response: \(detail)"
            case let .spawnFailed(message):
                return "Failed to spawn CLI session: \(message)"
            }
        }
    }

    enum State {
        case idle          // Not spawned
        case spawning      // Process launched, waiting for init message
        case ready         // Received init, waiting for user request
        case busy          // Processing a correction
        case dead          // Process exited or was killed
    }

    // MARK: - Properties

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var outputBuffer = Data()
    private let outputCondition = NSCondition()

    private(set) var state: State = .idle
    private(set) var sessionId: String?

    // MARK: - Spawn

    /// Launch the CLI process in stream-json mode. Returns immediately;
    /// the session transitions to `.ready` once the init message arrives.
    func spawn(
        executablePath: String,
        provider: CLIProvider,
        model: String,
        systemPrompt: String,
        environment: [String: String],
        workingDirectoryURL: URL?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        // Tear down any existing process.
        teardownLocked()

        guard provider == .claude else {
            throw SessionError.spawnFailed(
                "Persistent session only supports Claude provider (stream-json mode)."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        if let dir = workingDirectoryURL {
            process.currentDirectoryURL = dir
        }

        var args = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--no-session-persistence",
            "--tools", "",
            "--system-prompt", systemPrompt
        ]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--model", trimmedModel])
        }
        process.arguments = args

        var env = environment
        env.removeValue(forKey: "CLAUDE_CODE")
        env.removeValue(forKey: "CLAUDECODE")
        process.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        outputBuffer.removeAll(keepingCapacity: true)

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.outputCondition.lock()
            self.outputBuffer.append(data)
            self.outputCondition.signal()
            self.outputCondition.unlock()
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            self.state = .dead
            self.lock.unlock()
            // Wake anyone waiting for output so they see the dead state.
            self.outputCondition.lock()
            self.outputCondition.signal()
            self.outputCondition.unlock()
        }

        do {
            try process.run()
        } catch {
            throw SessionError.spawnFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading
        self.stderrHandle = errPipe.fileHandleForReading
        self.state = .spawning

        // Wait for the init message in the background so `spawn()` returns quickly.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.waitForInit(timeoutSeconds: 30)
        }
    }

    // MARK: - Send a correction

    /// Send a user message and block until the full result arrives.
    /// Must be called from a background thread.
    func send(prompt: String, timeoutSeconds: Int) throws -> StreamResult {
        lock.lock()
        guard state == .ready else {
            let current = state
            lock.unlock()
            throw current == .busy
                ? SessionError.notReady
                : SessionError.processExited(code: -1)
        }
        state = .busy
        lock.unlock()

        defer {
            lock.lock()
            if state == .busy { state = .ready }
            lock.unlock()
        }

        // Build the NDJSON user message.
        let messagePayload: [String: Any] = [
            "type": "user_message",
            "content": prompt
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: messagePayload),
              var jsonLine = String(data: jsonData, encoding: .utf8) else {
            throw SessionError.malformedResponse(detail: "Could not encode user message")
        }
        jsonLine += "\n"

        guard let lineData = jsonLine.data(using: .utf8) else {
            throw SessionError.malformedResponse(detail: "Could not encode to UTF-8")
        }

        // Clear buffer before sending.
        outputCondition.lock()
        outputBuffer.removeAll(keepingCapacity: true)
        outputCondition.unlock()

        // Write to stdin.
        lock.lock()
        guard let stdinHandle else {
            lock.unlock()
            throw SessionError.notReady
        }
        lock.unlock()

        do {
            try stdinHandle.write(contentsOf: lineData)
        } catch {
            markDead()
            throw SessionError.processExited(code: -1)
        }

        // Wait for the result message.
        return try waitForResult(timeoutSeconds: timeoutSeconds)
    }

    /// Send a user message and stream partial results via `onChunk`.
    /// The callback receives the accumulated text so far (called on main queue).
    /// Must be called from a background thread.
    func sendStreaming(
        prompt: String,
        timeoutSeconds: Int,
        onChunk: @escaping (String) -> Void
    ) throws -> StreamResult {
        lock.lock()
        guard state == .ready else {
            let current = state
            lock.unlock()
            throw current == .busy
                ? SessionError.notReady
                : SessionError.processExited(code: -1)
        }
        state = .busy
        lock.unlock()

        defer {
            lock.lock()
            if state == .busy { state = .ready }
            lock.unlock()
        }

        let messagePayload: [String: Any] = [
            "type": "user_message",
            "content": prompt
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: messagePayload),
              var jsonLine = String(data: jsonData, encoding: .utf8) else {
            throw SessionError.malformedResponse(detail: "Could not encode user message")
        }
        jsonLine += "\n"

        guard let lineData = jsonLine.data(using: .utf8) else {
            throw SessionError.malformedResponse(detail: "Could not encode to UTF-8")
        }

        outputCondition.lock()
        outputBuffer.removeAll(keepingCapacity: true)
        outputCondition.unlock()

        lock.lock()
        guard let stdinHandle else {
            lock.unlock()
            throw SessionError.notReady
        }
        lock.unlock()

        do {
            try stdinHandle.write(contentsOf: lineData)
        } catch {
            markDead()
            throw SessionError.processExited(code: -1)
        }

        return try waitForResultStreaming(timeoutSeconds: timeoutSeconds, onChunk: onChunk)
    }

    // MARK: - State queries

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .ready
    }

    var isAlive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .spawning || state == .ready || state == .busy
    }

    // MARK: - Teardown

    func kill() {
        lock.lock()
        teardownLocked()
        lock.unlock()
    }

    deinit {
        lock.lock()
        teardownLocked()
        lock.unlock()
    }

    // MARK: - Private

    private func teardownLocked() {
        stdoutHandle?.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        try? stderrHandle?.close()

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        state = .dead
        sessionId = nil

        outputCondition.lock()
        outputBuffer.removeAll(keepingCapacity: true)
        outputCondition.signal()
        outputCondition.unlock()
    }

    private func markDead() {
        lock.lock()
        state = .dead
        lock.unlock()
    }

    /// Block until we see `{"type":"system","subtype":"init",...}` on stdout.
    private func waitForInit(timeoutSeconds: Int) {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while true {
            outputCondition.lock()

            if checkDead() {
                outputCondition.unlock()
                return
            }

            if let initMsg = extractNextJSONLine() {
                outputCondition.unlock()
                if let type = initMsg["type"] as? String, type == "system",
                   let subtype = initMsg["subtype"] as? String, subtype == "init" {
                    let sid = initMsg["session_id"] as? String
                    lock.lock()
                    sessionId = sid
                    state = .ready
                    lock.unlock()
                    return
                }
                // Not the init message — keep waiting.
                continue
            }

            if Date() >= deadline {
                outputCondition.unlock()
                lock.lock()
                teardownLocked()
                lock.unlock()
                return
            }

            outputCondition.wait(until: Date().addingTimeInterval(0.1))
            outputCondition.unlock()
        }
    }

    /// Block until we see a `{"type":"result",...}` message.
    private func waitForResult(timeoutSeconds: Int) throws -> StreamResult {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while true {
            outputCondition.lock()

            if checkDead() {
                outputCondition.unlock()
                throw SessionError.processExited(code: process?.terminationStatus ?? -1)
            }

            if let msg = extractNextJSONLine() {
                outputCondition.unlock()

                if let result = extractResult(from: msg) {
                    return result
                }
                // Not a result message (could be assistant, stream_event, etc.) — keep reading.
                continue
            }

            if Date() >= deadline {
                outputCondition.unlock()
                markDead()
                throw SessionError.timedOut(seconds: timeoutSeconds)
            }

            outputCondition.wait(until: Date().addingTimeInterval(0.05))
            outputCondition.unlock()
        }
    }

    /// Block until result, streaming partial text via `onChunk`.
    private func waitForResultStreaming(
        timeoutSeconds: Int,
        onChunk: @escaping (String) -> Void
    ) throws -> StreamResult {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var accumulatedText = ""

        while true {
            outputCondition.lock()

            if checkDead() {
                outputCondition.unlock()
                throw SessionError.processExited(code: process?.terminationStatus ?? -1)
            }

            if let msg = extractNextJSONLine() {
                outputCondition.unlock()

                // Extract partial text from assistant messages or stream_events.
                if let partialText = extractPartialText(from: msg) {
                    accumulatedText = partialText
                    let snapshot = accumulatedText
                    DispatchQueue.main.async { onChunk(snapshot) }
                }

                if let result = extractResult(from: msg) {
                    return result
                }
                continue
            }

            if Date() >= deadline {
                outputCondition.unlock()
                markDead()
                throw SessionError.timedOut(seconds: timeoutSeconds)
            }

            outputCondition.wait(until: Date().addingTimeInterval(0.05))
            outputCondition.unlock()
        }
    }

    private func checkDead() -> Bool {
        lock.lock()
        let dead = state == .dead
        lock.unlock()
        return dead
    }

    /// Try to extract and consume the next complete NDJSON line from the output buffer.
    /// Must be called with `outputCondition` locked.
    private func extractNextJSONLine() -> [String: Any]? {
        let text = String(decoding: outputBuffer, as: UTF8.self)
        guard let newlineIndex = text.firstIndex(of: "\n") else {
            return nil
        }

        let line = String(text[text.startIndex..<newlineIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Consume this line from the buffer.
        let consumedCount = text[...newlineIndex].utf8.count
        if consumedCount <= outputBuffer.count {
            outputBuffer.removeFirst(consumedCount)
        } else {
            outputBuffer.removeAll(keepingCapacity: true)
        }

        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    /// Extract the final corrected text from a `result` message.
    private func extractResult(from json: [String: Any]) -> StreamResult? {
        guard let type = json["type"] as? String, type == "result" else {
            return nil
        }

        // The result text can be in "result" key directly.
        if let resultText = json["result"] as? String, !resultText.isEmpty {
            return StreamResult(text: resultText)
        }

        return StreamResult(text: "")
    }

    /// Extract partial/accumulated text from assistant messages for streaming.
    private func extractPartialText(from json: [String: Any]) -> String? {
        guard let type = json["type"] as? String else { return nil }

        if type == "assistant",
           let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            // Concatenate all text blocks.
            let texts = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            if !texts.isEmpty {
                return texts.joined()
            }
        }

        return nil
    }
}
