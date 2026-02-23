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

    func testAppendTokenAwareInstructionExtendsPromptWithEmojiRule() {
        let prompt = TokenPreservationSupport.appendTokenAwareInstruction(to: "Fix grammar.")
        XCTAssertTrue(prompt.contains("Fix grammar."))
        XCTAssertTrue(prompt.contains("Slack emoji codes"))
        XCTAssertTrue(prompt.contains("@mentions"))
        XCTAssertTrue(prompt.contains("MUST keep"))
    }

    // MARK: - splitAroundTokens

    func testSplitAroundTokensReturnsWholeTextWhenNoTokens() {
        let result = TokenPreservationSupport.splitAroundTokens(in: "No tokens here.")
        XCTAssertEqual(result.textParts, ["No tokens here."])
        XCTAssertTrue(result.tokens.isEmpty)
    }

    func testSplitAroundTokensSplitsAroundSingleEmoji() {
        let result = TokenPreservationSupport.splitAroundTokens(in: "I am :sad: today.")
        XCTAssertEqual(result.textParts, ["I am ", " today."])
        XCTAssertEqual(result.tokens, [":sad:"])
    }

    func testSplitAroundTokensSplitsAroundMultipleEmojis() {
        let result = TokenPreservationSupport.splitAroundTokens(in: "I am :sad: and :mad: about this.")
        XCTAssertEqual(result.textParts, ["I am ", " and ", " about this."])
        XCTAssertEqual(result.tokens, [":sad:", ":mad:"])
    }

    func testSplitAroundTokensSplitsAroundMixedTokenTypes() {
        let result = TokenPreservationSupport.splitAroundTokens(in: "Ask @naresh about :hat: please.")
        XCTAssertEqual(result.textParts, ["Ask ", " about ", " please."])
        XCTAssertEqual(result.tokens, ["@naresh", ":hat:"])
    }

    func testSplitAroundTokensHandlesTokenAtStart() {
        let result = TokenPreservationSupport.splitAroundTokens(in: ":wave: hello!")
        XCTAssertEqual(result.textParts, ["", " hello!"])
        XCTAssertEqual(result.tokens, [":wave:"])
    }

    func testSplitAroundTokensHandlesTokenAtEnd() {
        let result = TokenPreservationSupport.splitAroundTokens(in: "Good job :thumbsup:")
        XCTAssertEqual(result.textParts, ["Good job ", ""])
        XCTAssertEqual(result.tokens, [":thumbsup:"])
    }

    func testSplitAroundTokensHandlesAdjacentTokens() {
        let result = TokenPreservationSupport.splitAroundTokens(in: ":sad::mad:")
        XCTAssertEqual(result.textParts, ["", "", ""])
        XCTAssertEqual(result.tokens, [":sad:", ":mad:"])
    }

    // MARK: - reassemble

    func testReassembleJoinsPartsAndTokens() {
        let result = TokenPreservationSupport.reassemble(
            correctedParts: ["I am ", " and ", " about this."],
            tokens: [":sad:", ":mad:"]
        )
        XCTAssertEqual(result, "I am :sad: and :mad: about this.")
    }

    func testReassembleWithSingleToken() {
        let result = TokenPreservationSupport.reassemble(
            correctedParts: ["Hello ", " world."],
            tokens: [":wave:"]
        )
        XCTAssertEqual(result, "Hello :wave: world.")
    }

    func testReassembleWithNoTokens() {
        let result = TokenPreservationSupport.reassemble(
            correctedParts: ["Plain text."],
            tokens: []
        )
        XCTAssertEqual(result, "Plain text.")
    }

    func testReassemblePreservesEmptyParts() {
        let result = TokenPreservationSupport.reassemble(
            correctedParts: ["", " hello ", ""],
            tokens: [":wave:", ":smile:"]
        )
        XCTAssertEqual(result, ":wave: hello :smile:")
    }

    // MARK: - stripTokens

    func testStripTokensReplacesTokensWithSpace() {
        let result = TokenPreservationSupport.stripTokens(from: "I am :sad: and :mad: about this.")
        XCTAssertEqual(result, "I am   and   about this.")
    }

    func testStripTokensReturnsOriginalWhenNoTokens() {
        let result = TokenPreservationSupport.stripTokens(from: "No tokens here.")
        XCTAssertEqual(result, "No tokens here.")
    }

    func testStripTokensHandlesMixedTokenTypes() {
        let result = TokenPreservationSupport.stripTokens(from: "Ask @naresh about :hat: at /tmp/file.txt please.")
        XCTAssertEqual(result, "Ask   about   at   please.")
    }

    func testStripTokensHandlesTokenAtStartAndEnd() {
        let result = TokenPreservationSupport.stripTokens(from: ":wave: hello :smile:")
        XCTAssertEqual(result, "  hello  ")
    }

    // MARK: - Round-trip: split → reassemble preserves original

    func testSplitThenReassembleIsIdentity() {
        let original = "I am :sad: and :mad: about :100: things at /tmp/log.txt please."
        let split = TokenPreservationSupport.splitAroundTokens(in: original)
        let reassembled = TokenPreservationSupport.reassemble(
            correctedParts: split.textParts,
            tokens: split.tokens
        )
        XCTAssertEqual(reassembled, original)
    }

    // MARK: - recoverObjectReplacements

    func testRecoverObjectReplacementsRecoversSlackEmojis() {
        let plain = "Hello \u{FFFC} world \u{FFFC} done."
        let html = """
        Hello <img src="x" alt=":wave:"> world <img src="y" alt=":smile:"> done.
        """
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, "Hello :wave: world :smile: done.")
    }

    func testRecoverObjectReplacementsReturnsOriginalWhenNoFFFC() {
        let plain = "No replacement chars here."
        let html = "<p>No replacement chars here.</p>"
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, plain)
    }

    func testRecoverObjectReplacementsReturnsOriginalWhenHTMLIsNil() {
        let plain = "Has \u{FFFC} but no HTML."
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: nil)
        XCTAssertEqual(result, plain)
    }

    func testRecoverObjectReplacementsReturnsOriginalWhenCountMismatch() {
        let plain = "One \u{FFFC} two \u{FFFC} three."
        let html = """
        One <img src="x" alt=":wave:"> two three.
        """
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        // 2 U+FFFC but only 1 <img> — can't align, return original.
        XCTAssertEqual(result, plain)
    }

    func testRecoverObjectReplacementsReturnsOriginalWhenNoImgTags() {
        let plain = "Has \u{FFFC} char."
        let html = "<p>Has something.</p>"
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, plain)
    }

    func testRecoverObjectReplacementsHandlesSingleEmoji() {
        let plain = "bug \u{FFFC} report"
        let html = #"bug <img src="e" alt=":no-bugs:" class="emoji"> report"#
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, "bug :no-bugs: report")
    }

    func testRecoverObjectReplacementsHandlesImgWithoutAlt() {
        // When <img> has no alt attribute, extractImgAltValues won't find an alt
        // for that tag, so count will mismatch → returns original.
        let plain = "Has \u{FFFC} here."
        let html = #"Has <img src="x"> here."#
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, plain)
    }

    func testRecoverObjectReplacementsPreservesNonEmojiAltText() {
        // Alt text that isn't an emoji code is still recovered (it's the
        // best representation we have for the image).
        let plain = "See \u{FFFC} here."
        let html = #"See <img src="x" alt="screenshot"> here."#
        let result = TokenPreservationSupport.recoverObjectReplacements(in: plain, fromHTML: html)
        XCTAssertEqual(result, "See screenshot here.")
    }

    // MARK: - extractImgAltValues

    func testExtractImgAltValuesFindsMultipleAlts() {
        let html = #"<img alt=":wave:"><img src="x" alt=":smile:" class="c">"#
        let result = TokenPreservationSupport.extractImgAltValues(from: html)
        XCTAssertEqual(result, [":wave:", ":smile:"])
    }

    func testExtractImgAltValuesReturnsEmptyForNoImgs() {
        let result = TokenPreservationSupport.extractImgAltValues(from: "<p>No images.</p>")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractImgAltValuesSkipsImgWithoutAlt() {
        let html = #"<img src="x"><img src="y" alt=":ok:">"#
        let result = TokenPreservationSupport.extractImgAltValues(from: html)
        XCTAssertEqual(result, [":ok:"])
    }

    func testExtractImgAltValuesHandlesCaseInsensitive() {
        let html = #"<IMG ALT=":wave:" SRC="x">"#
        let result = TokenPreservationSupport.extractImgAltValues(from: html)
        XCTAssertEqual(result, [":wave:"])
    }

    func testSplitThenReassembleWithCorrectedParts() {
        let original = "i am :sad: and :mad: about the delay"
        let split = TokenPreservationSupport.splitAroundTokens(in: original)
        // Simulate AI correcting only the text parts
        let correctedParts = ["I am ", " and ", " about the delay."]
        let reassembled = TokenPreservationSupport.reassemble(
            correctedParts: correctedParts,
            tokens: split.tokens
        )
        XCTAssertEqual(reassembled, "I am :sad: and :mad: about the delay.")
    }
}
