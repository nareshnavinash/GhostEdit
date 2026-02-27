import AppKit

final class StreamingPreviewController: NSWindowController {
    private let originalText: String
    private let onAccept: (String) -> Void
    private let onCancel: () -> Void
    var onRegenerate: () -> Void

    private let leftTextView = NSTextView()
    private let rightTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let acceptButton: NSButton
    private let regenerateButton: NSButton
    private let cancelButton: NSButton
    private let leftScrollView = NSScrollView()
    private let rightScrollView = NSScrollView()
    private let statsLabel = NSTextField(labelWithString: "")

    private var latestCorrectedText = ""
    private(set) var isComplete = false

    // Change navigation (Item 31)
    private let prevChangeButton = NSButton()
    private let nextChangeButton = NSButton()
    private var changeRanges: [(left: NSRange, right: NSRange)] = []
    private var currentChangeIndex: Int = -1

    init(
        originalText: String,
        onAccept: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onRegenerate: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.onAccept = onAccept
        self.onCancel = onCancel
        self.onRegenerate = onRegenerate
        self.acceptButton = NSButton(title: "Accept (Tab)", target: nil, action: nil)
        self.regenerateButton = NSButton(title: "Regenerate (R)", target: nil, action: nil)
        self.cancelButton = NSButton(title: "Cancel (Esc)", target: nil, action: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Streaming Preview"
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("GhostEditStreamingPreview")
        if !window.setFrameUsingName("GhostEditStreamingPreview") { window.center() }
        window.minSize = NSSize(width: 600, height: 350)
        super.init(window: window)
        acceptButton.target = self
        acceptButton.action = #selector(acceptClicked)
        regenerateButton.target = self
        regenerateButton.action = #selector(regenerateClicked)
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateStreaming(accumulatedText: String) {
        let charCount = accumulatedText.count
        statusLabel.stringValue = StreamingPreviewSupport.streamingStatus(charCount: charCount)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        rightTextView.textStorage?.setAttributedString(
            NSAttributedString(string: accumulatedText, attributes: attrs)
        )
    }

    func markComplete(correctedText: String) {
        isComplete = true
        latestCorrectedText = correctedText

        let wordDiff = DiffSupport.wordDiff(old: originalText, new: correctedText)
        let changeCount = StreamingPreviewSupport.changeCount(from: wordDiff)
        statusLabel.stringValue = StreamingPreviewSupport.completedStatus(changeCount: changeCount)
        acceptButton.isEnabled = changeCount > 0
        regenerateButton.isEnabled = true

        // Stats bar
        let summary = DiffSupport.changeSummary(segments: wordDiff)
        let similarity = computeSimilarity(old: originalText, new: correctedText)
        statsLabel.stringValue = "\(summary) · \(similarity)% similarity"
        statsLabel.isHidden = false

        // Character-level diff for precise highlighting
        let charDiff = DiffSupport.charDiff(old: originalText, new: correctedText)

        // Side-by-side: left shows original with deletions highlighted,
        // right shows corrected with insertions highlighted.
        leftTextView.textStorage?.setAttributedString(buildOriginalSide(from: charDiff))
        rightTextView.textStorage?.setAttributedString(buildCorrectedSide(from: charDiff))

        // Build change ranges for navigation
        changeRanges = buildChangeRanges(from: charDiff)
        currentChangeIndex = -1
        updateNavButtonStates()
    }

    private func computeSimilarity(old: String, new: String) -> Int {
        let maxLen = max(old.count, new.count)
        guard maxLen > 0 else { return 100 }
        let diff = DiffSupport.wordDiff(old: old, new: new)
        let equalChars = diff.filter { $0.kind == .equal }.map(\.text).joined().count
        return Int(round(Double(equalChars) / Double(maxLen) * 100))
    }

    func resetForRegeneration() {
        isComplete = false
        latestCorrectedText = ""
        acceptButton.isEnabled = false
        regenerateButton.isEnabled = false
        statusLabel.stringValue = "Regenerating..."
        statsLabel.isHidden = true
        changeRanges = []
        currentChangeIndex = -1
        updateNavButtonStates()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        rightTextView.textStorage?.setAttributedString(
            NSAttributedString(string: "Waiting for response...", attributes: attrs)
        )

        // Reset the original side back to plain
        let origAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        leftTextView.textStorage?.setAttributedString(
            NSAttributedString(string: originalText, attributes: origAttrs)
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && isComplete { // Tab key
            acceptClicked()
        } else if event.keyCode == 53 { // Esc key
            cancelClicked()
        } else if event.keyCode == 15 && isComplete { // R key
            regenerateClicked()
        } else {
            super.keyDown(with: event)
        }
    }

    private func buildUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Status bar
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Waiting for response..."
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Column headers with tinted backgrounds
        let originalHeaderBg = NSView()
        originalHeaderBg.wantsLayer = true
        originalHeaderBg.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.06).cgColor
        originalHeaderBg.layer?.cornerRadius = 4
        originalHeaderBg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(originalHeaderBg)

        let originalHeader = NSTextField(labelWithString: "Original")
        originalHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        originalHeader.textColor = .systemRed.withAlphaComponent(0.8)
        originalHeader.translatesAutoresizingMaskIntoConstraints = false
        originalHeaderBg.addSubview(originalHeader)

        let correctedHeaderBg = NSView()
        correctedHeaderBg.wantsLayer = true
        correctedHeaderBg.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.06).cgColor
        correctedHeaderBg.layer?.cornerRadius = 4
        correctedHeaderBg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(correctedHeaderBg)

        let correctedHeader = NSTextField(labelWithString: "Corrected")
        correctedHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        correctedHeader.textColor = .systemGreen.withAlphaComponent(0.8)
        correctedHeader.translatesAutoresizingMaskIntoConstraints = false
        correctedHeaderBg.addSubview(correctedHeader)

        // Left scroll view (original text)
        configureTextView(leftTextView, in: leftScrollView)
        contentView.addSubview(leftScrollView)

        // Right scroll view (corrected text)
        configureTextView(rightTextView, in: rightScrollView)
        contentView.addSubview(rightScrollView)

        // Populate left side with original text
        let origAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        leftTextView.textStorage?.setAttributedString(
            NSAttributedString(string: originalText, attributes: origAttrs)
        )

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        // Buttons — styled: Accept is green accent, Cancel is plain
        acceptButton.keyEquivalent = "\t"
        acceptButton.bezelStyle = .rounded
        acceptButton.contentTintColor = .white
        acceptButton.wantsLayer = true
        acceptButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        acceptButton.layer?.cornerRadius = 5
        acceptButton.isEnabled = false
        acceptButton.translatesAutoresizingMaskIntoConstraints = false

        regenerateButton.isEnabled = false
        regenerateButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        // Stats bar (hidden until completion)
        statsLabel.font = .systemFont(ofSize: 11)
        statsLabel.textColor = .tertiaryLabelColor
        statsLabel.isHidden = true
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsLabel)

        // Change navigation buttons (Item 31)
        prevChangeButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous Change")
        prevChangeButton.bezelStyle = .rounded
        prevChangeButton.isBordered = true
        prevChangeButton.toolTip = "Previous Change"
        prevChangeButton.isEnabled = false
        prevChangeButton.target = self
        prevChangeButton.action = #selector(prevChangeClicked)
        prevChangeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(prevChangeButton)

        nextChangeButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next Change")
        nextChangeButton.bezelStyle = .rounded
        nextChangeButton.isBordered = true
        nextChangeButton.toolTip = "Next Change"
        nextChangeButton.isEnabled = false
        nextChangeButton.target = self
        nextChangeButton.action = #selector(nextChangeClicked)
        nextChangeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nextChangeButton)

        contentView.addSubview(acceptButton)
        contentView.addSubview(regenerateButton)
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Original header background
            originalHeaderBg.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            originalHeaderBg.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            originalHeader.topAnchor.constraint(equalTo: originalHeaderBg.topAnchor, constant: 3),
            originalHeader.bottomAnchor.constraint(equalTo: originalHeaderBg.bottomAnchor, constant: -3),
            originalHeader.leadingAnchor.constraint(equalTo: originalHeaderBg.leadingAnchor, constant: 8),
            originalHeader.trailingAnchor.constraint(equalTo: originalHeaderBg.trailingAnchor, constant: -8),

            // Corrected header background
            correctedHeaderBg.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            correctedHeaderBg.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 4),
            correctedHeader.topAnchor.constraint(equalTo: correctedHeaderBg.topAnchor, constant: 3),
            correctedHeader.bottomAnchor.constraint(equalTo: correctedHeaderBg.bottomAnchor, constant: -3),
            correctedHeader.leadingAnchor.constraint(equalTo: correctedHeaderBg.leadingAnchor, constant: 8),
            correctedHeader.trailingAnchor.constraint(equalTo: correctedHeaderBg.trailingAnchor, constant: -8),

            leftScrollView.topAnchor.constraint(equalTo: originalHeaderBg.bottomAnchor, constant: 4),
            leftScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            leftScrollView.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -4),
            leftScrollView.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -6),
            leftScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            divider.topAnchor.constraint(equalTo: originalHeaderBg.bottomAnchor, constant: 4),
            divider.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -6),

            rightScrollView.topAnchor.constraint(equalTo: correctedHeaderBg.bottomAnchor, constant: 4),
            rightScrollView.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 4),
            rightScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            rightScrollView.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -6),
            rightScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            statsLabel.leadingAnchor.constraint(equalTo: nextChangeButton.trailingAnchor, constant: 8),
            statsLabel.bottomAnchor.constraint(equalTo: acceptButton.topAnchor, constant: -6),

            // Change navigation buttons — left side of stats bar
            prevChangeButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            prevChangeButton.centerYAnchor.constraint(equalTo: statsLabel.centerYAnchor),
            prevChangeButton.widthAnchor.constraint(equalToConstant: 28),

            nextChangeButton.leadingAnchor.constraint(equalTo: prevChangeButton.trailingAnchor, constant: 2),
            nextChangeButton.centerYAnchor.constraint(equalTo: statsLabel.centerYAnchor),
            nextChangeButton.widthAnchor.constraint(equalToConstant: 28),

            acceptButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            acceptButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            acceptButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            regenerateButton.trailingAnchor.constraint(equalTo: acceptButton.leadingAnchor, constant: -8),
            regenerateButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            regenerateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            cancelButton.trailingAnchor.constraint(equalTo: regenerateButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
    }

    private func configureTextView(_ textView: NSTextView, in scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false

        // Line numbers (Item 29)
        scrollView.hasHorizontalRuler = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        scrollView.documentView = textView
    }

    private func buildOriginalSide(from segments: [DiffSegment]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: 13)
        for segment in segments {
            switch segment.kind {
            case .equal:
                result.append(NSAttributedString(string: segment.text, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor
                ]))
            case .deletion:
                result.append(NSAttributedString(string: segment.text, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.12),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]))
            case .insertion:
                break // Don't show insertions on the original side
            }
        }
        return result
    }

    private func buildCorrectedSide(from segments: [DiffSegment]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: 13)
        for segment in segments {
            switch segment.kind {
            case .equal:
                result.append(NSAttributedString(string: segment.text, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor
                ]))
            case .insertion:
                result.append(NSAttributedString(string: segment.text, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.12),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]))
            case .deletion:
                break // Don't show deletions on the corrected side
            }
        }
        return result
    }

    // MARK: - Change Navigation (Item 31)

    private func buildChangeRanges(from segments: [DiffSegment]) -> [(left: NSRange, right: NSRange)] {
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
                    // Merge adjacent deletion+insertion into one change
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

    private func updateNavButtonStates() {
        let hasChanges = !changeRanges.isEmpty
        prevChangeButton.isEnabled = hasChanges && currentChangeIndex > 0
        nextChangeButton.isEnabled = hasChanges && currentChangeIndex < changeRanges.count - 1
    }

    @objc private func prevChangeClicked() {
        guard currentChangeIndex > 0 else { return }
        currentChangeIndex -= 1
        scrollToCurrentChange()
        updateNavButtonStates()
    }

    @objc private func nextChangeClicked() {
        guard currentChangeIndex < changeRanges.count - 1 else { return }
        currentChangeIndex += 1
        scrollToCurrentChange()
        updateNavButtonStates()
    }

    private func scrollToCurrentChange() {
        guard changeRanges.indices.contains(currentChangeIndex) else { return }
        let change = changeRanges[currentChangeIndex]

        // Scroll left side to the deletion
        if change.left.length > 0 {
            leftTextView.scrollRangeToVisible(change.left)
            leftTextView.setSelectedRange(change.left)
        } else {
            leftTextView.scrollRangeToVisible(NSRange(location: change.left.location, length: 0))
        }

        // Scroll right side to the insertion
        if change.right.length > 0 {
            rightTextView.scrollRangeToVisible(change.right)
            rightTextView.setSelectedRange(change.right)
        } else {
            rightTextView.scrollRangeToVisible(NSRange(location: change.right.location, length: 0))
        }
    }

    @objc private func acceptClicked() {
        guard isComplete else { return }
        window?.close()
        onAccept(latestCorrectedText)
    }

    @objc private func regenerateClicked() {
        guard isComplete else { return }
        resetForRegeneration()
        onRegenerate()
    }

    @objc private func cancelClicked() {
        window?.close()
        onCancel()
    }
}

// MARK: - Flipped Clip View (top-aligned scroll content)

final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - Line Number Ruler View (Item 29)

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private static let rulerWidth: CGFloat = 36
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private static let textColor = NSColor.tertiaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = Self.rulerWidth
        clientView = textView

        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? rect
        let textInset = textView.textContainerInset

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect, in: textContainer
        )
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        let text = textView.string as NSString
        var lineNumber = 1

        // Count lines before visible range
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: visibleCharRange.location),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in
            lineNumber += 1
        }

        // Draw line numbers for visible lines
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: Self.textColor
        ]

        text.enumerateSubstrings(
            in: visibleCharRange,
            options: [.byLines, .substringNotRequired]
        ) { _, substringRange, _, _ in
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: substringRange.location, length: 0),
                actualCharacterRange: nil
            )
            var lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location, effectiveRange: nil
            )
            lineRect.origin.y += textInset.height - visibleRect.origin.y

            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: Self.rulerWidth - strSize.width - 5,
                y: lineRect.origin.y + (lineRect.height - strSize.height) / 2
            )
            numStr.draw(at: drawPoint, withAttributes: attrs)
            lineNumber += 1
        }
    }
}
