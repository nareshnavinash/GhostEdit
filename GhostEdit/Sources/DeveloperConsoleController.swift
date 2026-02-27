import AppKit

final class DeveloperConsoleController: NSWindowController {
    private let textView = NSTextView()
    private var entries: [DeveloperModeLogEntry] = []
    private let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DeveloperModeSupport.windowWidth,
                height: DeveloperModeSupport.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostEdit Developer Console"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("GhostEditDeveloperConsole")
        if !window.setFrameUsingName("GhostEditDeveloperConsole") { window.center() }

        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func appendEntry(_ entry: DeveloperModeLogEntry) {
        entries.append(entry)
        if entries.count > DeveloperModeSupport.maxEntries {
            entries.removeFirst(entries.count - DeveloperModeSupport.maxEntries)
        }

        let line = DeveloperModeSupport.formatEntry(entry, formatter: logFormatter) + "\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: colorForPhase(entry.phase)
        ]
        textView.textStorage?.append(NSAttributedString(string: line, attributes: attrs))
        textView.scrollToEndOfDocument(nil)
    }

    func clearLog() {
        entries.removeAll()
        textView.string = ""
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearClicked))
        let copyButton = NSButton(title: "Copy All", target: self, action: #selector(copyAllClicked))

        toolbar.addArrangedSubview(clearButton)
        toolbar.addArrangedSubview(copyButton)
        toolbar.addArrangedSubview(NSView()) // spacer

        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func colorForPhase(_ phase: DeveloperModeLogEntry.Phase) -> NSColor {
        switch phase {
        case .textCapture:
            return .systemBlue
        case .tokenProtection:
            return .systemPurple
        case .cliResolution:
            return .systemOrange
        case .cliExecution:
            return .systemGreen
        case .cliResponse:
            return .systemTeal
        case .tokenRestoration:
            return .systemPurple
        case .pasteBack:
            return .systemIndigo
        }
    }

    @objc private func clearClicked() {
        clearLog()
    }

    @objc private func copyAllClicked() {
        let allText = DeveloperModeSupport.formatAllEntries(entries, formatter: logFormatter)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
    }
}
