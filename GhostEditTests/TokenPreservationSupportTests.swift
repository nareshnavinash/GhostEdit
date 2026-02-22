import XCTest
@testable import GhostEditCore

final class TokenPreservationSupportTests: XCTestCase {
    func testProtectTokensReturnsOriginalTextWhenNoSlackTokensExist() {
        let result = TokenPreservationSupport.protectTokens(in: "This is plain text.")
        XCTAssertEqual(result.protectedText, "This is plain text.")
        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertFalse(result.hasProtectedTokens)
    }

    func testProtectTokensReplacesMentionsAndEmojiInOrder() {
        let input = "Hey @<U123> please add :hat: and :cat:."
        let result = TokenPreservationSupport.protectTokens(in: input)

        XCTAssertEqual(
            result.tokens,
            [
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "@<U123>"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: ":hat:"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_2__", originalToken: ":cat:")
            ]
        )
        XCTAssertEqual(
            result.protectedText,
            "Hey __GHOSTEDIT_KEEP_0__ please add __GHOSTEDIT_KEEP_1__ and __GHOSTEDIT_KEEP_2__."
        )
        XCTAssertTrue(result.hasProtectedTokens)
    }

    func testProtectTokensAvoidsPlaceholderCollisionsInSourceText() {
        let input = "Already has __GHOSTEDIT_KEEP_0__ plus :hat:"
        let result = TokenPreservationSupport.protectTokens(in: input)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].originalToken, ":hat:")
        XCTAssertEqual(result.tokens[0].placeholder, "__GHOSTEDIT_KEEP_0_1__")
        XCTAssertEqual(result.protectedText, "Already has __GHOSTEDIT_KEEP_0__ plus __GHOSTEDIT_KEEP_0_1__")
    }

    func testAppendInstructionExtendsPromptWithPlaceholderRule() {
        let prompt = TokenPreservationSupport.appendInstruction(to: "Fix grammar.")
        XCTAssertTrue(prompt.contains("Fix grammar."))
        XCTAssertTrue(prompt.contains("Important token-preservation rule"))
        XCTAssertTrue(prompt.contains("__GHOSTEDIT_KEEP_0__"))
    }

    func testPlaceholdersAreIntactRequiresExactlyOneOccurrencePerPlaceholder() {
        let tokens = [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "@<U1>"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: ":hat:")
        ]

        XCTAssertTrue(
            TokenPreservationSupport.placeholdersAreIntact(
                in: "Hello __GHOSTEDIT_KEEP_0__ and __GHOSTEDIT_KEEP_1__.",
                tokens: tokens
            )
        )
        XCTAssertFalse(
            TokenPreservationSupport.placeholdersAreIntact(
                in: "Hello __GHOSTEDIT_KEEP_0__ only.",
                tokens: tokens
            )
        )
        XCTAssertFalse(
            TokenPreservationSupport.placeholdersAreIntact(
                in: "__GHOSTEDIT_KEEP_0__ __GHOSTEDIT_KEEP_0__ and __GHOSTEDIT_KEEP_1__.",
                tokens: tokens
            )
        )
    }

    func testRestoreTokensReplacesEveryPlaceholderWithOriginalToken() {
        let tokens = [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "@<U1>"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: ":hat:")
        ]
        let restored = TokenPreservationSupport.restoreTokens(
            in: "Hi __GHOSTEDIT_KEEP_0__ add __GHOSTEDIT_KEEP_1__.",
            tokens: tokens
        )
        XCTAssertEqual(restored, "Hi @<U1> add :hat:.")
    }
}
