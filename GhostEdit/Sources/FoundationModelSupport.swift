import Foundation
import FoundationModels

@available(macOS 26, *)
enum FoundationModelSupport {
    /// The system prompt for grammar correction.
    static let grammarCorrectionPrompt = """
        You are a grammar, spelling, and punctuation correction assistant. \
        Fix all errors in the provided text. Return ONLY the corrected text \
        without any explanations, comments, or markdown formatting. \
        Preserve the original meaning, tone, and proper nouns (names, brands, places). \
        If the text has no errors, return it unchanged.
        """

    /// Returns true if on-device Foundation Models are available.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Correct text using the on-device Foundation Model.
    static func correctText(_ input: String) async throws -> String {
        guard isAvailable else {
            throw FoundationModelError.modelNotAvailable
        }
        let session = LanguageModelSession(instructions: grammarCorrectionPrompt)
        let response = try await session.respond(to: input)
        return response.content
    }

    enum FoundationModelError: Error {
        case modelNotAvailable
    }
}
