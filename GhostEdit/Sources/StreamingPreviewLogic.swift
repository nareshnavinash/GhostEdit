import Foundation

enum StreamingPreviewLogic {
    /// Compute the similarity percentage between two strings using word-level diff.
    static func computeSimilarity(old: String, new: String) -> Int {
        let maxLen = max(old.count, new.count)
        guard maxLen > 0 else { return 100 }
        let diff = DiffSupport.wordDiff(old: old, new: new)
        let equalChars = diff.filter { $0.kind == .equal }.map(\.text).joined().count
        return Int(round(Double(equalChars) / Double(maxLen) * 100))
    }

    /// Build navigable change ranges from diff segments.
    /// Returns pairs of (left: range in original, right: range in corrected).
    /// Adjacent deletion+insertion pairs are merged into single changes.
    static func buildChangeRanges(from segments: [DiffSegment]) -> [(left: NSRange, right: NSRange)] {
        var ranges: [(left: NSRange, right: NSRange)] = []
        var leftOffset = 0
        var rightOffset = 0
        for segment in segments {
            let len = segment.text.utf16.count
            switch segment.kind {
            case .equal:
                leftOffset += len
                rightOffset += len
            case .deletion:
                ranges.append((left: NSRange(location: leftOffset, length: len),
                                right: NSRange(location: rightOffset, length: 0)))
                leftOffset += len
            case .insertion:
                if let last = ranges.last, last.right.location + last.right.length == rightOffset,
                   last.left.location + last.left.length == leftOffset {
                    ranges[ranges.count - 1] = (left: last.left,
                                                  right: NSRange(location: last.right.location, length: len))
                } else {
                    ranges.append((left: NSRange(location: leftOffset, length: 0),
                                    right: NSRange(location: rightOffset, length: len)))
                }
                rightOffset += len
            }
        }
        return ranges
    }

    /// Determine enabled state for prev/next navigation buttons.
    static func navButtonStates(changeCount: Int, currentIndex: Int) -> (prevEnabled: Bool, nextEnabled: Bool) {
        let hasChanges = changeCount > 0
        return (
            prevEnabled: hasChanges && currentIndex > 0,
            nextEnabled: hasChanges && currentIndex < changeCount - 1
        )
    }

    /// Check if prev navigation is possible.
    static func canNavigatePrev(currentIndex: Int) -> Bool {
        return currentIndex > 0
    }

    /// Check if next navigation is possible.
    static func canNavigateNext(currentIndex: Int, totalChanges: Int) -> Bool {
        return currentIndex < totalChanges - 1
    }
}
