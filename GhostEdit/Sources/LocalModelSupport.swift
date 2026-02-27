import Foundation

enum LocalModelStatus: String, Codable, Equatable {
    case notDownloaded
    case downloading
    case ready
    case error
}

struct LocalModelEntry: Codable, Equatable {
    var repoID: String
    var displayName: String
    var parameterCount: String
    var approxDiskGB: Double
    var status: LocalModelStatus
    var localPath: String

    init(
        repoID: String,
        displayName: String,
        parameterCount: String,
        approxDiskGB: Double,
        status: LocalModelStatus = .notDownloaded,
        localPath: String = ""
    ) {
        self.repoID = repoID
        self.displayName = displayName
        self.parameterCount = parameterCount
        self.approxDiskGB = approxDiskGB
        self.status = status
        self.localPath = localPath
    }
}

enum LocalModelSupport {
    static let recommendedModels: [LocalModelEntry] = [
        LocalModelEntry(
            repoID: "grammarly/coedit-small",
            displayName: "CoEdIT Small",
            parameterCount: "77M",
            approxDiskGB: 0.3
        ),
        LocalModelEntry(
            repoID: "grammarly/coedit-base",
            displayName: "CoEdIT Base",
            parameterCount: "220M",
            approxDiskGB: 0.9
        ),
        LocalModelEntry(
            repoID: "grammarly/coedit-large",
            displayName: "CoEdIT Large",
            parameterCount: "770M",
            approxDiskGB: 3.0
        ),
        LocalModelEntry(
            repoID: "grammarly/coedit-xl",
            displayName: "CoEdIT XL",
            parameterCount: "3B",
            approxDiskGB: 11.0
        ),
    ]

    static func modelsDirectoryURL(baseDirectoryURL: URL) -> URL {
        baseDirectoryURL.appendingPathComponent("models", isDirectory: true)
    }

    static func modelDirectoryURL(baseDirectoryURL: URL, repoID: String) -> URL {
        let safeName = repoID.replacingOccurrences(of: "/", with: "--")
        return modelsDirectoryURL(baseDirectoryURL: baseDirectoryURL)
            .appendingPathComponent(safeName, isDirectory: true)
    }

    static func taskPrefix() -> String {
        "Fix grammatical errors in this sentence: "
    }

    static func isValidRepoID(_ repoID: String) -> Bool {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let org = parts[0]
        let model = parts[1]
        guard !org.isEmpty, !model.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard org.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              model.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return false
        }
        return true
    }

    static func extractRepoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidRepoID(trimmed) {
            return trimmed
        }
        // Try parsing as HuggingFace URL: https://huggingface.co/org/model
        guard let url = URL(string: trimmed),
              let host = url.host,
              host == "huggingface.co" || host == "www.huggingface.co" else {
            return nil
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        let repoID = "\(pathComponents[0])/\(pathComponents[1])"
        return isValidRepoID(repoID) ? repoID : nil
    }

    static func mergedModelList(
        saved: [LocalModelEntry],
        downloaded: Set<String>
    ) -> [LocalModelEntry] {
        var knownRepoIDs = Set<String>()
        var result: [LocalModelEntry] = []

        // Start with recommended models, updating status from saved/downloaded
        for var recommended in recommendedModels {
            knownRepoIDs.insert(recommended.repoID)
            if let savedEntry = saved.first(where: { $0.repoID == recommended.repoID }) {
                recommended.localPath = savedEntry.localPath
            }
            if downloaded.contains(recommended.repoID) {
                recommended.status = .ready
            } else {
                recommended.status = .notDownloaded
            }
            result.append(recommended)
        }

        // Append user-saved custom models not in the recommended list
        for var custom in saved where !knownRepoIDs.contains(custom.repoID) {
            knownRepoIDs.insert(custom.repoID)
            if downloaded.contains(custom.repoID) {
                custom.status = .ready
            } else {
                custom.status = .notDownloaded
            }
            result.append(custom)
        }

        return result
    }
}
