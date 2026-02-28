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
    var taskPrefix: String

    init(
        repoID: String,
        displayName: String,
        parameterCount: String,
        approxDiskGB: Double,
        status: LocalModelStatus = .notDownloaded,
        localPath: String = "",
        taskPrefix: String = "Fix grammatical errors in this sentence: "
    ) {
        self.repoID = repoID
        self.displayName = displayName
        self.parameterCount = parameterCount
        self.approxDiskGB = approxDiskGB
        self.status = status
        self.localPath = localPath
        self.taskPrefix = taskPrefix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repoID = try container.decode(String.self, forKey: .repoID)
        displayName = try container.decode(String.self, forKey: .displayName)
        parameterCount = try container.decode(String.self, forKey: .parameterCount)
        approxDiskGB = try container.decode(Double.self, forKey: .approxDiskGB)
        status = try container.decodeIfPresent(LocalModelStatus.self, forKey: .status) ?? .notDownloaded
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath) ?? ""
        taskPrefix = try container.decodeIfPresent(String.self, forKey: .taskPrefix) ?? "Fix grammatical errors in this sentence: "
    }
}

enum LocalModelSupport {
    static let fallbackPromptTemplate = """
Revise the following text by correcting grammar, spelling, and punctuation. Preserve meaning and line breaks. Return ONLY the corrected text.

{text}
"""

    static let recommendedModels: [LocalModelEntry] = [
        LocalModelEntry(
            repoID: "vennify/t5-base-grammar-correction",
            displayName: "T5 Base Grammar",
            parameterCount: "220M",
            approxDiskGB: 0.9,
            taskPrefix: "grammar: "
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

    static func taskPrefix(for repoID: String) -> String {
        if let entry = recommendedModels.first(where: { $0.repoID == repoID }) {
            return entry.taskPrefix
        }
        return "Fix grammatical errors in this sentence: "
    }

    static func defaultPromptTemplate(for repoID: String) -> String {
        if let entry = recommendedModels.first(where: { $0.repoID == repoID }) {
            return "\(entry.taskPrefix){text}"
        }
        return fallbackPromptTemplate
    }

    static func validatePromptTemplate(_ template: String) -> Bool {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("{text}")
    }

    static func promptTemplateOverrides(from config: AppConfig) -> [String: String] {
        guard let data = config.localModelPromptTemplates.data(using: .utf8),
              let overrides = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return overrides
    }

    static func resolvedPromptTemplate(for repoID: String, config: AppConfig) -> String {
        let overrides = promptTemplateOverrides(from: config)
        if let override = overrides[repoID], validatePromptTemplate(override) {
            return override
        }

        if let customData = config.localModelCustomModels.data(using: .utf8),
           let customModels = try? JSONDecoder().decode([LocalModelEntry].self, from: customData),
           let customEntry = customModels.first(where: { $0.repoID == repoID }) {
            return "\(customEntry.taskPrefix){text}"
        }

        return defaultPromptTemplate(for: repoID)
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
