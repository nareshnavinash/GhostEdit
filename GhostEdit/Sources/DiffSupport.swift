import Foundation

enum DiffSegmentKind: Equatable {
    case equal
    case insertion
    case deletion
}

struct DiffSegment: Equatable {
    let kind: DiffSegmentKind
    let text: String
}

enum DiffSupport {
    /// Compute a word-level diff between `old` and `new`.
    /// Returns an array of `DiffSegment` values indicating equal, inserted,
    /// and deleted runs.
    static func wordDiff(old: String, new: String) -> [DiffSegment] {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        let edits = myersDiff(old: oldTokens, new: newTokens)
        return coalesce(edits)
    }

    /// Returns `true` when `old` and `new` are identical after trimming.
    static func isIdentical(old: String, new: String) -> Bool {
        old.trimmingCharacters(in: .whitespacesAndNewlines)
            == new.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a compact summary such as "3 words changed, 1 added, 2 removed".
    static func changeSummary(segments: [DiffSegment]) -> String {
        var added = 0
        var removed = 0
        for segment in segments {
            switch segment.kind {
            case .insertion:
                added += wordCount(segment.text)
            case .deletion:
                removed += wordCount(segment.text)
            case .equal:
                break
            }
        }

        if added == 0 && removed == 0 {
            return "No changes"
        }

        var parts: [String] = []
        if added > 0 {
            parts.append("\(added) word\(added == 1 ? "" : "s") added")
        }
        if removed > 0 {
            parts.append("\(removed) word\(removed == 1 ? "" : "s") removed")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Tokenization

    /// Split text into alternating word/whitespace tokens to preserve spacing
    /// in the diff output.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var inWhitespace = text.first!.isWhitespace

        for char in text {
            if char.isWhitespace == inWhitespace {
                current.append(char)
            } else {
                tokens.append(current)
                current = String(char)
                inWhitespace = char.isWhitespace
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    // MARK: - Myers diff (simple O(ND) algorithm)

    private enum Edit: Equatable {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    private static func myersDiff(old: [String], new: [String]) -> [Edit] {
        let n = old.count
        let m = new.count
        let maxD = n + m
        guard maxD > 0 else { return [] }

        // V[k] stores the furthest-reaching x-coordinate on diagonal k.
        // Diagonals range from -maxD to +maxD, so we offset by maxD.
        var v = Array(repeating: 0, count: 2 * maxD + 1)
        var trace: [[Int]] = []

        outer: for d in 0...maxD {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                let idx = k + maxD
                var x: Int
                if d == 0 {
                    x = 0
                } else if k == -d || (k != d && v[idx - 1] < v[idx + 1]) {
                    x = v[idx + 1]
                } else {
                    x = v[idx - 1] + 1
                }
                var y = x - k
                while x < n && y < m && old[x] == new[y] {
                    x += 1
                    y += 1
                }
                v[idx] = x
                if x >= n && y >= m {
                    break outer
                }
            }
        }

        // Backtrack to recover the edit sequence.
        var edits: [Edit] = []
        var x = n
        var y = m
        for d in stride(from: trace.count - 1, through: 1, by: -1) {
            let curr = trace[d]
            let k = x - y
            let idx = k + maxD
            let prevK: Int
            if k == -(d) || (k != d && curr.indices.contains(idx - 1) && curr.indices.contains(idx + 1) && curr[idx - 1] < curr[idx + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }

            let prevIdx = prevK + maxD
            let prevX = curr[prevIdx]
            let prevY = prevX - prevK

            // Diagonal (equal) moves.
            while x > prevX && y > prevY {
                x -= 1
                y -= 1
                edits.append(.equal(old[x]))
            }

            if y > prevY {
                y -= 1
                edits.append(.insert(new[y]))
            } else if x > prevX {
                x -= 1
                edits.append(.delete(old[x]))
            }
        }

        // Remaining diagonals at d=0.
        while x > 0 && y > 0 {
            x -= 1
            y -= 1
            edits.append(.equal(old[x]))
        }

        edits.reverse()
        return edits
    }

    // MARK: - Coalescing

    private static func coalesce(_ edits: [Edit]) -> [DiffSegment] {
        guard !edits.isEmpty else { return [] }

        var segments: [DiffSegment] = []
        var currentKind: DiffSegmentKind?
        var currentText = ""

        for edit in edits {
            let kind: DiffSegmentKind
            let text: String
            switch edit {
            case .equal(let t): kind = .equal; text = t
            case .insert(let t): kind = .insertion; text = t
            case .delete(let t): kind = .deletion; text = t
            }

            if kind == currentKind {
                currentText += text
            } else {
                if let k = currentKind {
                    segments.append(DiffSegment(kind: k, text: currentText))
                }
                currentKind = kind
                currentText = text
            }
        }

        if let k = currentKind {
            segments.append(DiffSegment(kind: k, text: currentText))
        }

        return segments
    }

    /// Compute a character-level diff between `old` and `new`.
    /// More precise than wordDiff for showing exact changes.
    static func charDiff(old: String, new: String) -> [DiffSegment] {
        let oldChars = Array(old).map { String($0) }
        let newChars = Array(new).map { String($0) }
        let edits = myersDiff(old: oldChars, new: newChars)
        return coalesce(edits)
    }

    // MARK: - Helpers

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
