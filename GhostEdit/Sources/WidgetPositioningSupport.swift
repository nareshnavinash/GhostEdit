import CoreGraphics
import Foundation

enum WidgetPositioningSupport {
    /// Compute the widget origin given the text field's AX bounds.
    /// Positions widget below the text field, aligned to its right edge.
    /// Falls back to above the field if there's no space below.
    static func widgetOrigin(
        fieldPosition: CGPoint,
        fieldSize: CGSize,
        screenHeight: CGFloat,
        visibleMinY: CGFloat,
        widgetWidth: CGFloat,
        widgetHeight: CGFloat
    ) -> CGPoint {
        let widgetX = fieldPosition.x + fieldSize.width - widgetWidth
        let fieldBottomY = screenHeight - (fieldPosition.y + fieldSize.height)
        let widgetY = fieldBottomY - widgetHeight - 8

        let finalY: CGFloat
        if widgetY < visibleMinY {
            finalY = screenHeight - fieldPosition.y + 8
        } else {
            finalY = widgetY
        }

        return CGPoint(x: max(0, widgetX), y: max(0, finalY))
    }

    /// Fallback widget position when AX bounds are unavailable.
    static func widgetFallbackOrigin(
        screenMaxX: CGFloat,
        screenMinY: CGFloat,
        widgetWidth: CGFloat
    ) -> CGPoint {
        let x = screenMaxX - widgetWidth - 20
        let y = screenMinY + 20
        return CGPoint(x: x, y: y)
    }

    /// Compute popover origin relative to the widget frame, clamped to screen bounds.
    static func popoverOrigin(
        widgetFrame: CGRect,
        popoverSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        var popoverX = widgetFrame.origin.x
        var popoverY = widgetFrame.origin.y + widgetFrame.height + 4

        // Vertical: if popover overflows top, place below widget
        if popoverY + popoverSize.height > visibleFrame.maxY {
            popoverY = widgetFrame.origin.y - popoverSize.height - 4
        }
        // Horizontal: clamp so popover doesn't go off the right or left edge
        if popoverX + popoverSize.width > visibleFrame.maxX {
            popoverX = visibleFrame.maxX - popoverSize.width
        }
        if popoverX < visibleFrame.minX {
            popoverX = visibleFrame.minX
        }

        return CGPoint(x: popoverX, y: popoverY)
    }

    /// Determine whether to reposition the widget based on drag state.
    enum RepositionDecision: Equatable {
        case reposition
        case skipDragged
        case resetDragFlag
    }

    static func shouldReposition(
        widgetManuallyDragged: Bool,
        currentFocusedPID: Int32?,
        lastDraggedForPID: Int32?
    ) -> RepositionDecision {
        if let pid = currentFocusedPID, pid != lastDraggedForPID {
            return .resetDragFlag
        }
        if widgetManuallyDragged {
            return .skipDragged
        }
        return .reposition
    }

    /// Adjust issues after a fix is applied — shift ranges for issues after the fixed location.
    static func adjustIssuesAfterFix(
        issues: [SpellCheckIssue],
        fixedIndex: Int,
        originalRange: NSRange,
        replacementLength: Int
    ) -> [SpellCheckIssue] {
        let lengthDelta = replacementLength - originalRange.length
        var updated: [SpellCheckIssue] = []
        for (index, issue) in issues.enumerated() {
            if index == fixedIndex { continue }
            if issue.range.location >= originalRange.location + originalRange.length {
                let newRange = NSRange(
                    location: issue.range.location + lengthDelta,
                    length: issue.range.length
                )
                updated.append(SpellCheckIssue(
                    word: issue.word, range: newRange,
                    kind: issue.kind, suggestions: issue.suggestions
                ))
            } else {
                updated.append(issue)
            }
        }
        return updated
    }
}
