import Foundation

struct HardwareInfo: Equatable {
    var totalRAMBytes: UInt64
    var availableDiskBytes: UInt64
    var architecture: String
}

enum ModelRecommendation: String, Equatable {
    case recommended
    case compatible
    case notRecommended
}

enum HardwareCompatibilitySupport {
    static func estimatedRAMGB(modelDiskGB: Double) -> Double {
        modelDiskGB * 2.0
    }

    static func recommendation(modelDiskGB: Double, hardware: HardwareInfo) -> ModelRecommendation {
        let diskGB = Double(hardware.availableDiskBytes) / 1_073_741_824.0
        let ramGB = Double(hardware.totalRAMBytes) / 1_073_741_824.0
        let requiredDisk = modelDiskGB * 1.2
        let requiredRAM = estimatedRAMGB(modelDiskGB: modelDiskGB)

        guard diskGB >= requiredDisk, ramGB >= requiredRAM else {
            return .notRecommended
        }
        if ramGB >= modelDiskGB * 3.0 {
            return .recommended
        }
        return .compatible
    }

    static func parseMemsize(_ output: String) -> UInt64? {
        // Expected: "hw.memsize: 17179869184" or just "17179869184"
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colonIndex = trimmed.lastIndex(of: ":") {
            let valueStr = trimmed[trimmed.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)
            return UInt64(valueStr)
        }
        return UInt64(trimmed)
    }

    static func parseDiskSpace(_ output: String) -> UInt64? {
        // Parses `df -k /` output. Format:
        // Filesystem   1024-blocks     Used Available Capacity  ...
        // /dev/disk3s1 488245288  234567890 253677398    48%    ...
        let lines = output.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return nil }
        let dataLine = lines[1].trimmingCharacters(in: .whitespaces)
        let columns = dataLine.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 4 else { return nil }
        guard let availableKB = UInt64(columns[3]) else { return nil }
        return availableKB * 1024
    }

    static func parseArchitecture(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    static func recommendationLabel(_ recommendation: ModelRecommendation) -> String {
        switch recommendation {
        case .recommended:
            return "Recommended"
        case .compatible:
            return "Compatible"
        case .notRecommended:
            return "Not Recommended"
        }
    }

    static func recommendationColor(_ recommendation: ModelRecommendation) -> String {
        switch recommendation {
        case .recommended:
            return "green"
        case .compatible:
            return "orange"
        case .notRecommended:
            return "red"
        }
    }
}
