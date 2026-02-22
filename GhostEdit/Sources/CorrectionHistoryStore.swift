import Foundation

struct CorrectionHistoryEntry: Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var originalText: String
    var generatedText: String
    var provider: String
    var model: String
    var durationMilliseconds: Int
    var succeeded: Bool
}

final class CorrectionHistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func bootstrapIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try "[]\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func load() -> [CorrectionHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()
    }

    func append(_ entry: CorrectionHistoryEntry, limit: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        var entries = readLocked()
        entries.append(entry)
        let normalized = normalizedEntries(entries, limit: limit)
        try writeLocked(normalized)
    }

    func trim(limit: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        let entries = readLocked()
        let normalized = normalizedEntries(entries, limit: limit)
        try writeLocked(normalized)
    }

    private func normalizedEntries(_ entries: [CorrectionHistoryEntry], limit: Int) -> [CorrectionHistoryEntry] {
        let normalizedLimit = max(1, limit)
        guard entries.count > normalizedLimit else {
            return entries
        }
        return Array(entries.suffix(normalizedLimit))
    }

    private func readLocked() -> [CorrectionHistoryEntry] {
        guard
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CorrectionHistoryEntry].self, from: data)) ?? []
    }

    private func writeLocked(_ entries: [CorrectionHistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
