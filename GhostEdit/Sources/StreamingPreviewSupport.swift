import Foundation

/// Pure-logic support for the streaming preview feature.
/// Keeps UI-free calculations testable.
enum StreamingPreviewSupport {
    /// Build an attributed-string description of the diff between original and corrected text.
    /// Returns an array of (text, kind) tuples suitable for rendering.
    struct StyledSegment: Equatable {
        enum Kind: Equatable {
            case unchanged
            case added
            case removed
        }

        let text: String
        let kind: Kind
    }

    /// Produce styled segments from a word-level diff.
    static func styledSegments(from diffSegments: [DiffSegment]) -> [StyledSegment] {
        diffSegments.map { segment in
            switch segment.kind {
            case .equal:
                return StyledSegment(text: segment.text, kind: .unchanged)
            case .insertion:
                return StyledSegment(text: segment.text, kind: .added)
            case .deletion:
                return StyledSegment(text: segment.text, kind: .removed)
            }
        }
    }

    /// Extract only the "new" text (equal + insertions) from diff segments.
    static func correctedText(from diffSegments: [DiffSegment]) -> String {
        diffSegments
            .filter { $0.kind != .deletion }
            .map(\.text)
            .joined()
    }

    /// Returns a short status string for the streaming state.
    static func streamingStatus(charCount: Int) -> String {
        "Receiving... (\(charCount) chars)"
    }

    /// Returns a status string for the completed state.
    static func completedStatus(changeCount: Int) -> String {
        if changeCount == 0 {
            return "No changes detected"
        }
        return "\(changeCount) change\(changeCount == 1 ? "" : "s") — press Tab to accept, Esc to cancel"
    }

    /// Count the number of changed segments (insertions + deletions).
    static func changeCount(from diffSegments: [DiffSegment]) -> Int {
        diffSegments.filter { $0.kind != .equal }.count
    }
}
