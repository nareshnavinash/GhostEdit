import Foundation

enum PythonEnvironmentStatus: Equatable {
    case ready
    case pythonNotFound
    case pythonTooOld(version: String)
    case packagesNotInstalled(missing: [String])
}

enum PythonEnvironmentSupport {
    static let requiredPackages: [String] = ["transformers", "torch"]

    static func parsePythonVersion(_ output: String) -> (Int, Int, Int)? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Expected format: "Python 3.11.2" or just "3.11.2"
        let versionString: String
        if trimmed.lowercased().hasPrefix("python ") {
            versionString = String(trimmed.dropFirst("Python ".count))
        } else {
            versionString = trimmed
        }
        let parts = versionString.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        let patch = parts.count >= 3 ? (Int(parts[2]) ?? 0) : 0
        return (major, minor, patch)
    }

    static func meetsMinimumVersion(major: Int, minor: Int) -> Bool {
        if major > 3 { return true }
        if major < 3 { return false }
        return minor >= 9
    }

    static func pipInstallCommand(pythonPath: String) -> String {
        "\(pythonPath) -m pip install --upgrade --break-system-packages --index-url https://pypi.org/simple/ transformers torch jinja2 markupsafe"
    }

    static func parseInstalledPackages(_ output: String) -> Set<String> {
        var packages = Set<String>()
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip header lines from pip list
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("Package") { continue }
            // pip list format: "package-name    version"
            let columns = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let name = columns.first {
                packages.insert(String(name).lowercased())
            }
        }
        return packages
    }

    static func missingPackages(installed: Set<String>) -> [String] {
        let normalizedInstalled = Set(installed.map { $0.lowercased() })
        return requiredPackages.filter { !normalizedInstalled.contains($0.lowercased()) }
    }

    static func detectPythonPath(homeDirectoryPath: String, searchPaths: [String]? = nil) -> String {
        for path in (searchPaths ?? pythonSearchPaths(homeDirectoryPath: homeDirectoryPath)) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/bin/python3"
    }

    static func pythonSearchPaths(homeDirectoryPath: String) -> [String] {
        [
            // Python.framework installs (pip works without --break-system-packages)
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            // Homebrew (PEP 668 externally-managed, needs --break-system-packages)
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            // User-local installs
            "\(homeDirectoryPath)/Library/Python/3.13/bin/python3",
            "\(homeDirectoryPath)/Library/Python/3.12/bin/python3",
            "\(homeDirectoryPath)/Library/Python/3.11/bin/python3",
            "\(homeDirectoryPath)/Library/Python/3.10/bin/python3",
            "\(homeDirectoryPath)/Library/Python/3.9/bin/python3",
            // System Python (last resort)
            "/usr/bin/python3",
        ]
    }
}
