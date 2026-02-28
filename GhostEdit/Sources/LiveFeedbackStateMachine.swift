import Foundation

enum LiveFeedbackStateMachine {
    enum Event: Equatable {
        case textChanged(String)
        case textUnchanged
        case spellCheckComplete([SpellCheckIssue])
        case focusLost
        case stopped
    }

    enum SideEffect: Equatable {
        case runSpellCheck(String)
        case showIssues([SpellCheckIssue])
        case clearUI
    }

    /// Pure state transition: given current state and event, return next state and side effects.
    static func transition(
        state: LiveFeedbackState,
        event: Event
    ) -> (state: LiveFeedbackState, sideEffects: [SideEffect]) {
        switch (state, event) {
        // Text changed → start checking
        case (_, .textChanged(let text)):
            return (.checking, [.runSpellCheck(text)])

        // Text unchanged while already checking → stay in checking
        case (.checking, .textUnchanged):
            return (.checking, [])

        // Text unchanged in other states → no change
        case (_, .textUnchanged):
            return (state, [])

        // Spell check complete → update state based on results
        case (_, .spellCheckComplete(let issues)):
            if issues.isEmpty {
                return (.clean, [.clearUI])
            } else {
                return (.issues(issues.count), [.showIssues(issues)])
            }

        // Focus lost → go idle
        case (_, .focusLost):
            return (.idle, [.clearUI])

        // Stopped → go idle
        case (_, .stopped):
            return (.idle, [.clearUI])
        }
    }

    /// Check if a model check result is still valid given the current generation.
    static func isResultStale(resultGeneration: Int, currentGeneration: Int) -> Bool {
        return resultGeneration != currentGeneration
    }

    /// Determine the combined issue list from spell check + model check,
    /// filtering out ignored words and deduplicating by range.
    static func combineIssues(
        spellCheckIssues: [SpellCheckIssue],
        modelIssues: [SpellCheckIssue],
        ignoredWords: Set<String>
    ) -> [SpellCheckIssue] {
        var combined = spellCheckIssues
        for issue in modelIssues {
            let overlaps = combined.contains { existing in
                existing.range.intersection(issue.range) != nil
            }
            if !overlaps {
                combined.append(issue)
            }
        }
        return combined.filter { !ignoredWords.contains($0.word.lowercased()) }
    }
}
