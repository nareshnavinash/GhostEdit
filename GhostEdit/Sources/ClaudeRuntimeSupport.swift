import Foundation

enum ClaudeRuntimeSupport {
    static func cliSearchPaths(
        provider: CLIProvider,
        homeDirectoryPath: String,
        environment: [String: String]
    ) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        let executableName = provider.executableName

        func appendUnique(_ path: String) {
            guard !path.isEmpty else { return }
            let expanded = NSString(string: path).expandingTildeInPath
            guard !expanded.isEmpty, !seen.contains(expanded) else {
                return
            }
            seen.insert(expanded)
            paths.append(expanded)
        }

        appendUnique("\(homeDirectoryPath)/.local/bin/\(executableName)")
        appendUnique("/opt/homebrew/bin/\(executableName)")
        appendUnique("/usr/local/bin/\(executableName)")
        appendUnique("/usr/bin/\(executableName)")
        appendUnique("\(homeDirectoryPath)/bin/\(executableName)")

        if let envPath = environment["PATH"] {
            for directory in envPath.split(separator: ":") {
                appendUnique("\(directory)/\(executableName)")
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
        provider: CLIProvider,
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> ShellRunnerError {
        let normalized = "\(stdout)\n\(stderr)".lowercased()
        if normalized.contains("failed to authenticate")
            || normalized.contains("authentication_error")
            || normalized.contains("token has expired")
            || normalized.contains("oauth token")
            || normalized.contains("\(provider.executableName) login")
            || normalized.contains("\(provider.executableName) auth login")
            || normalized.contains("api error: 401")
            || normalized.contains("unauthorized")
            || normalized.contains("invalid credentials") {
            return .authenticationRequired(provider: provider)
        }

        let preferredDetails = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? stdout
            : stderr
        return .processFailed(exitCode: exitCode, stderr: preferredDetails)
    }

    static func cliArguments(provider: CLIProvider, prompt: String, model: String) -> [String] {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .claude:
            var args = [
                "-p",
                prompt,
                "--setting-sources",
                "user",
                "--tools",
                ""
            ]
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            return args
        case .codex:
            var args = [
                "exec",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "-c",
                "model_reasoning_effort='low'"
            ]
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(prompt)
            return args
        case .gemini:
            var args = [
                "--prompt",
                prompt,
                "--output-format",
                "text"
            ]
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            return args
        }
    }

    static func claudeSearchPaths(homeDirectoryPath: String, environment: [String: String]) -> [String] {
        cliSearchPaths(provider: .claude, homeDirectoryPath: homeDirectoryPath, environment: environment)
    }

    static func claudeArguments(prompt: String, model: String) -> [String] {
        cliArguments(provider: .claude, prompt: prompt, model: model)
    }
}
