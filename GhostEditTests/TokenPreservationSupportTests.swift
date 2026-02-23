import XCTest
@testable import GhostEditCore

final class TokenPreservationSupportTests: XCTestCase {
    func testProtectTokensReturnsOriginalTextWhenNoSlackTokensExist() {
        let result = TokenPreservationSupport.protectTokens(in: "This is plain text.")
        XCTAssertEqual(result.protectedText, "This is plain text.")
        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertFalse(result.hasProtectedTokens)
    }

    func testProtectTokensReplacesMentionsAndStaticItemsInOrder() {
        let input = "Ping @naresh and @<U123>. Check /tmp/file.txt, docs/readme.md, https://example.com/p, `git status`, :hat:, and a@b.com."
        let result = TokenPreservationSupport.protectTokens(in: input)

        XCTAssertEqual(
            result.tokens,
            [
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "@naresh"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: "@<U123>"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_2__", originalToken: "/tmp/file.txt"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_3__", originalToken: "docs/readme.md"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_4__", originalToken: "https://example.com/p"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_5__", originalToken: "`git status`"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_6__", originalToken: ":hat:"),
                ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_7__", originalToken: "a@b.com")
            ]
        )
        XCTAssertEqual(
            result.protectedText,
            "Ping __GHOSTEDIT_KEEP_0__ and __GHOSTEDIT_KEEP_1__. Check __GHOSTEDIT_KEEP_2__, __GHOSTEDIT_KEEP_3__, __GHOSTEDIT_KEEP_4__, __GHOSTEDIT_KEEP_5__, __GHOSTEDIT_KEEP_6__, and __GHOSTEDIT_KEEP_7__."
        )
        XCTAssertTrue(result.hasProtectedTokens)
    }

    func testProtectTokensSupportsAngleBracketMentionSyntax() {
        let result = TokenPreservationSupport.protectTokens(in: "Assign to <@U12345> now.")
        XCTAssertEqual(result.tokens, [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "<@U12345>")
        ])
        XCTAssertEqual(result.protectedText, "Assign to __GHOSTEDIT_KEEP_0__ now.")
    }

    func testProtectTokensPrefersSingleURLWhenPathSubstringsOverlap() {
        let input = "Open https://example.com/team/docs/readme.md now."
        let result = TokenPreservationSupport.protectTokens(in: input)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens.first?.originalToken, "https://example.com/team/docs/readme.md")
        XCTAssertEqual(result.protectedText, "Open __GHOSTEDIT_KEEP_0__ now.")
    }

    func testProtectTokensPreservesEmailAndSeparateMention() {
        let input = "Email a@b.com and message @editor."
        let result = TokenPreservationSupport.protectTokens(in: input)

        XCTAssertEqual(result.tokens, [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: "a@b.com"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: "@editor")
        ])
        XCTAssertEqual(result.protectedText, "Email __GHOSTEDIT_KEEP_0__ and message __GHOSTEDIT_KEEP_1__.")
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
        XCTAssertTrue(prompt.contains("URLs"))
        XCTAssertTrue(prompt.contains("file paths"))
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

    // MARK: - bestEffortRestore

    func testBestEffortRestoreRestoresSurvivingPlaceholders() {
        let tokens = [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: ":sad:"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: ":mad:"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_2__", originalToken: "@user")
        ]
        // AI kept placeholder 0 and 2 but removed 1.
        let output = "I am __GHOSTEDIT_KEEP_0__ about __GHOSTEDIT_KEEP_2__ leaving."
        let result = TokenPreservationSupport.bestEffortRestore(in: output, tokens: tokens)
        XCTAssertEqual(result, "I am :sad: about @user leaving.")
    }

    func testBestEffortRestoreReturnsUnchangedWhenNoPlaceholdersSurvive() {
        let tokens = [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: ":hat:")
        ]
        let output = "All placeholders were removed by AI."
        let result = TokenPreservationSupport.bestEffortRestore(in: output, tokens: tokens)
        XCTAssertEqual(result, output)
    }

    func testBestEffortRestoreRestoresAllWhenAllSurvive() {
        let tokens = [
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_0__", originalToken: ":sad:"),
            ProtectedToken(placeholder: "__GHOSTEDIT_KEEP_1__", originalToken: ":mad:")
        ]
        let output = "Feeling __GHOSTEDIT_KEEP_0__ and __GHOSTEDIT_KEEP_1__."
        let result = TokenPreservationSupport.bestEffortRestore(in: output, tokens: tokens)
        XCTAssertEqual(result, "Feeling :sad: and :mad:.")
    }

    func testBestEffortRestoreWithEmptyTokensList() {
        let result = TokenPreservationSupport.bestEffortRestore(in: "No tokens here.", tokens: [])
        XCTAssertEqual(result, "No tokens here.")
    }

    // MARK: - Slack emoji protection

    func testProtectTokensCatchesCommonSlackEmojis() {
        let input = "Good job :thumbsup: but I am :sad: and :mad: about the delay."
        let result = TokenPreservationSupport.protectTokens(in: input)

        let emojiTokens = result.tokens.map(\.originalToken)
        XCTAssertTrue(emojiTokens.contains(":thumbsup:"))
        XCTAssertTrue(emojiTokens.contains(":sad:"))
        XCTAssertTrue(emojiTokens.contains(":mad:"))
        XCTAssertFalse(result.protectedText.contains(":sad:"))
        XCTAssertFalse(result.protectedText.contains(":mad:"))
        XCTAssertFalse(result.protectedText.contains(":thumbsup:"))
    }

    func testProtectTokensCatchesEmojiWithHyphensAndNumbers() {
        let input = "Check :+1: and :100: and :e-mail:."
        let result = TokenPreservationSupport.protectTokens(in: input)

        let emojiTokens = result.tokens.map(\.originalToken)
        XCTAssertTrue(emojiTokens.contains(":+1:"))
        XCTAssertTrue(emojiTokens.contains(":100:"))
        XCTAssertTrue(emojiTokens.contains(":e-mail:"))
    }

    func testProtectTokensCatchesEmojiWithUnderscores() {
        let input = "Great :thumbs_up: work :heart_eyes:!"
        let result = TokenPreservationSupport.protectTokens(in: input)

        let emojiTokens = result.tokens.map(\.originalToken)
        XCTAssertTrue(emojiTokens.contains(":thumbs_up:"))
        XCTAssertTrue(emojiTokens.contains(":heart_eyes:"))
    }

    func testProtectTokensDoesNotMatchSingleColon() {
        let input = "Time: 3:00 PM and ratio is 2:1."
        let result = TokenPreservationSupport.protectTokens(in: input)

        // None of these should match the emoji pattern.
        let emojiTokens = result.tokens.filter { $0.originalToken.hasPrefix(":") && $0.originalToken.hasSuffix(":") }
        XCTAssertTrue(emojiTokens.isEmpty)
    }
}
