import Foundation

enum TokenEstimationSupport {
    /// Rough token estimate using a characters-per-token heuristic.
    /// English text averages ~4 characters per token for most LLMs.
    private static let charsPerToken: Double = 4.0

    /// Estimate token count for a piece of text.
    static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    /// Estimate total tokens used in a correction (input + output).
    static func estimateCorrectionTokens(
        systemPrompt: String,
        inputText: String,
        outputText: String
    ) -> (inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        let input = estimateTokens(for: systemPrompt) + estimateTokens(for: inputText)
        let output = estimateTokens(for: outputText)
        return (input, output, input + output)
    }

    /// Estimate cumulative tokens from history entries.
    static func estimateCumulativeTokens(
        entries: [CorrectionHistoryEntry],
        averagePromptLength: Int = 200
    ) -> (inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        var totalInput = 0
        var totalOutput = 0

        for entry in entries where entry.succeeded {
            let promptTokens = max(1, Int(ceil(Double(averagePromptLength) / charsPerToken)))
            let inputTokens = estimateTokens(for: entry.originalText)
            let outputTokens = estimateTokens(for: entry.generatedText)
            totalInput += promptTokens + inputTokens
            totalOutput += outputTokens
        }

        return (totalInput, totalOutput, totalInput + totalOutput)
    }

    /// Format a token count for display (e.g. "1.2k", "45.3k").
    static func formatTokenCount(_ count: Int) -> String {
        if count < 1_000 {
            return "\(count)"
        }
        if count < 1_000_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return String(format: "%.1fM", Double(count) / 1_000_000.0)
    }
}
