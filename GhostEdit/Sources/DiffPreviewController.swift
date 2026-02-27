import AppKit

final class DiffPreviewController: NSWindowController {
    private let segments: [DiffSegment]
    private let summary: String
    private let onApply: () -> Void
    private let onCancel: () -> Void

    init(
        segments: [DiffSegment],
        summary: String,
        onApply: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.segments = segments
        self.summary = summary
        self.onApply = onApply
        self.onCancel = onCancel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review Changes"
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("GhostEditDiffPreview")
        if !window.setFrameUsingName("GhostEditDiffPreview") { window.center() }
        window.minSize = NSSize(width: 400, height: 300)
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Summary label at top
        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summaryLabel)

        // Scrollable attributed text view showing the diff
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let attributed = buildAttributedDiff()
        textView.textStorage?.setAttributedString(attributed)

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // Buttons — green primary, plain secondary
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyClicked))
        applyButton.keyEquivalent = "\r"
        applyButton.bezelStyle = .rounded
        applyButton.contentTintColor = .white
        applyButton.wantsLayer = true
        applyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        applyButton.layer?.cornerRadius = 5
        applyButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(applyButton)
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -12),

            applyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            applyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            cancelButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        window.contentView = contentView
    }

    private func buildAttributedDiff() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        for segment in segments {
            let attrs: [NSAttributedString.Key: Any]
            switch segment.kind {
            case .equal:
                attrs = [.font: baseFont, .foregroundColor: NSColor.labelColor]
            case .insertion:
                attrs = [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            case .deletion:
                attrs = [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.15),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
            }
            result.append(NSAttributedString(string: segment.text, attributes: attrs))
        }

        return result
    }

    @objc private func applyClicked() {
        window?.close()
        onApply()
    }

    @objc private func cancelClicked() {
        window?.close()
        onCancel()
    }
}
