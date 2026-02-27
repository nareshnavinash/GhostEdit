import Foundation

final class LocalModelRunner {
    private let scriptName = "ghostedit_infer.py"

    // Persistent process state
    private var persistentProcess: Process?
    private var persistentStdin: FileHandle?
    private var persistentStdout: FileHandle?
    private var persistentPythonPath: String?
    private var stdoutBuffer = Data()
    private let bufferLock = NSLock()

    func correctText(_ input: String, modelPath: String, pythonPath: String, timeoutSeconds: Int) throws -> String {
        let request: [String: Any] = [
            "command": "infer",
            "model_path": modelPath,
            "text": input,
            "max_length": 256,
        ]

        // Try persistent process first for fast cached inference
        if let response = try? sendPersistentRequest(request, pythonPath: pythonPath, timeoutSeconds: timeoutSeconds) {
            guard let status = response["status"] as? String, status == "ok",
                  let corrected = response["corrected"] as? String else {
                let message = response["message"] as? String ?? "Unknown inference error"
                throw LocalModelRunnerError.inferenceFailed(message)
            }
            return corrected
        }

        // Fall back to one-shot
        let response = try runScript(request: request, pythonPath: pythonPath, timeoutSeconds: timeoutSeconds)
        guard let status = response["status"] as? String, status == "ok",
              let corrected = response["corrected"] as? String else {
            let message = response["message"] as? String ?? "Unknown inference error"
            throw LocalModelRunnerError.inferenceFailed(message)
        }
        return corrected
    }

    func downloadModel(
        repoID: String, destPath: String, pythonPath: String,
        onProgress: @escaping (String) -> Void
    ) throws {
        let request: [String: Any] = [
            "command": "download",
            "repo_id": repoID,
            "dest_path": destPath,
        ]
        let response = try runScript(
            request: request, pythonPath: pythonPath, timeoutSeconds: 600,
            stderrHandler: { line in
                onProgress(line)
            }
        )
        guard let status = response["status"] as? String, status == "ok" else {
            let message = response["message"] as? String ?? "Download failed"
            throw LocalModelRunnerError.downloadFailed(message)
        }
    }

    func checkPythonPackages(pythonPath: String) throws -> [String: Bool] {
        let request: [String: Any] = ["command": "check_packages"]
        let response = try runScript(request: request, pythonPath: pythonPath, timeoutSeconds: 30)
        guard let status = response["status"] as? String, status == "ok" else {
            let message = response["message"] as? String ?? "Package check failed"
            throw LocalModelRunnerError.packageCheckFailed(message)
        }
        let installed = response["installed"] as? [String] ?? []
        let missing = response["missing"] as? [String] ?? []
        var result: [String: Bool] = [:]
        for pkg in installed { result[pkg] = true }
        for pkg in missing { result[pkg] = false }
        return result
    }

    func gatherHardwareInfo() -> HardwareInfo {
        let memOutput = shell("/usr/sbin/sysctl", ["-n", "hw.memsize"])
        let dfOutput = shell("/bin/df", ["-k", "/"])
        let archOutput = shell("/usr/bin/uname", ["-m"])

        let ram = HardwareCompatibilitySupport.parseMemsize(memOutput) ?? 0
        let disk = HardwareCompatibilitySupport.parseDiskSpace(dfOutput) ?? 0
        let arch = HardwareCompatibilitySupport.parseArchitecture(archOutput)

        return HardwareInfo(totalRAMBytes: ram, availableDiskBytes: disk, architecture: arch)
    }

    func shutdown() {
        persistentProcess?.terminate()
        persistentProcess = nil
        persistentStdin = nil
        persistentStdout = nil
        persistentPythonPath = nil
        bufferLock.lock()
        stdoutBuffer = Data()
        bufferLock.unlock()
    }

    // MARK: - Persistent Process

    private func ensurePersistentProcess(pythonPath: String) throws {
        // Already running with same python path
        if let proc = persistentProcess, proc.isRunning, persistentPythonPath == pythonPath {
            return
        }

        // Terminate existing if different path or dead
        if persistentProcess != nil {
            shutdown()
        }

        guard let script = scriptPath() else {
            throw LocalModelRunnerError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [script, "--serve"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        persistentProcess = process
        persistentStdin = stdinPipe.fileHandleForWriting
        persistentStdout = stdoutPipe.fileHandleForReading
        persistentPythonPath = pythonPath

        bufferLock.lock()
        stdoutBuffer = Data()
        bufferLock.unlock()
    }

    private func sendPersistentRequest(
        _ request: [String: Any], pythonPath: String, timeoutSeconds: Int
    ) throws -> [String: Any] {
        try ensurePersistentProcess(pythonPath: pythonPath)

        guard let stdin = persistentStdin, let stdout = persistentStdout else {
            throw LocalModelRunnerError.invalidResponse
        }

        // Write request as single JSON line
        var requestData = try JSONSerialization.data(withJSONObject: request)
        requestData.append(contentsOf: [0x0A]) // newline
        stdin.write(requestData)

        // Read one line from stdout with timeout
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while true {
            if Date() > deadline {
                shutdown()
                throw LocalModelRunnerError.persistentProcessTimeout
            }

            // Read available data
            bufferLock.lock()
            let available = stdout.availableData
            if !available.isEmpty {
                stdoutBuffer.append(available)
            }

            // Check for newline in buffer
            if let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newlineIndex]
                stdoutBuffer = Data(stdoutBuffer[(newlineIndex + 1)...])
                bufferLock.unlock()

                guard let json = try JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] else {
                    throw LocalModelRunnerError.invalidResponse
                }
                return json
            }
            bufferLock.unlock()

            // Brief sleep to avoid busy-waiting
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    // MARK: - One-Shot

    private func scriptPath() -> String? {
        let homeScripts = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghostedit/scripts/\(scriptName)").path
        if FileManager.default.fileExists(atPath: homeScripts) {
            return homeScripts
        }
        return Bundle.main.path(forResource: "ghostedit_infer", ofType: "py")
    }

    private func runScript(
        request: [String: Any],
        pythonPath: String,
        timeoutSeconds: Int,
        stderrHandler: ((String) -> Void)? = nil
    ) throws -> [String: Any] {
        guard let script = scriptPath() else {
            throw LocalModelRunnerError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [script]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Write request JSON to stdin
        let requestData = try JSONSerialization.data(withJSONObject: request)
        inputPipe.fileHandleForWriting.write(requestData)
        inputPipe.fileHandleForWriting.closeFile()

        // Read stderr for progress updates (real-time via readabilityHandler)
        if let handler = stderrHandler {
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                    handler(line)
                }
            }
        }

        // Set up timeout
        let timeoutItem = DispatchWorkItem { [weak process] in
            process?.terminate()
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .seconds(timeoutSeconds),
            execute: timeoutItem
        )

        process.waitUntilExit()
        timeoutItem.cancel()
        errorPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw LocalModelRunnerError.processExitedWithError(Int(process.terminationStatus))
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw LocalModelRunnerError.invalidResponse
        }

        return json
    }

    private func shell(_ command: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

enum LocalModelRunnerError: LocalizedError {
    case scriptNotFound
    case inferenceFailed(String)
    case downloadFailed(String)
    case packageCheckFailed(String)
    case processExitedWithError(Int)
    case invalidResponse
    case persistentProcessTimeout

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Inference script (ghostedit_infer.py) not found"
        case .inferenceFailed(let msg):
            return "Inference failed: \(msg)"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .packageCheckFailed(let msg):
            return "Package check failed: \(msg)"
        case .processExitedWithError(let code):
            return "Python process exited with code \(code)"
        case .invalidResponse:
            return "Invalid response from Python script"
        case .persistentProcessTimeout:
            return "Persistent Python process timed out"
        }
    }
}
