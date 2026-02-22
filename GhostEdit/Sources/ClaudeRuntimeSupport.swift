import Foundation

enum ClaudeRuntimeSupport {
    static func claudeSearchPaths(homeDirectoryPath: String, environment: [String: String]) -> [String] {
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

        appendUnique("\(homeDirectoryPath)/.local/bin/claude")
        appendUnique("/opt/homebrew/bin/claude")
        appendUnique("/usr/local/bin/claude")
        appendUnique("/usr/bin/claude")
        appendUnique("\(homeDirectoryPath)/bin/claude")

        if let envPath = environment["PATH"] {
            for directory in envPath.split(separator: ":") {
                appendUnique("\(directory)/claude")
            }
        }

        return paths
    }

    static func runtimePathValue(homeDirectoryPath: String, environment: [String: String]) -> String {
        var components: [String] = []
        var seen = Set<String>()

        func appendUnique(_ value: String) {
            guard !value.isEmpty, !seen.contains(value) else { return }
            seen.insert(value)
            components.append(value)
        }

        if let existingPath = environment["PATH"] {
            for path in existingPath.split(separator: ":") {
                appendUnique(String(path))
            }
        }

        appendUnique("\(homeDirectoryPath)/.local/bin")
        appendUnique("/opt/homebrew/bin")
        appendUnique("/usr/local/bin")
        appendUnique("/usr/bin")
        appendUnique("/bin")
        appendUnique("/usr/sbin")
        appendUnique("/sbin")

        return components.joined(separator: ":")
    }

    static func classifyProcessFailure(
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> ShellRunnerError {
        let normalized = "\(stdout)\n\(stderr)".lowercased()
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

    static func claudeArguments(prompt: String, model: String) -> [String] {
        var args = [
            "-p",
            prompt,
            "--setting-sources",
            "user",
            "--tools",
            ""
        ]

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            args.append(contentsOf: ["--model", trimmedModel])
        }

        return args
    }
}
