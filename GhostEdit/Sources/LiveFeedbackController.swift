import AppKit

// MARK: - LiveFeedbackController

final class LiveFeedbackController {
    private var pollingTimer: Timer?
    private var debounceTimer: Timer?
    private var lastCheckedText: String?
    private var currentIssues: [SpellCheckIssue] = []
    private var state: LiveFeedbackState = .idle
    private var isPolling = false

    private let backgroundQueue = DispatchQueue(label: "com.ghostedit.livefeedback", qos: .userInitiated)

    private var widgetWindow: NSPanel?
    var widgetFrame: NSRect? { widgetWindow?.frame }
    private var widgetIconView: NSImageView?
    private var widgetDot: NSView?
    private var widgetDragOrigin: NSPoint?

    private var popoverPanel: NSPanel?
    private var popoverDismissTimer: Timer?
    private var isMouseInsidePopover: Bool = false

    private var currentFocusedPID: pid_t?
    private var currentCheckedText: String?
    private var widgetManuallyDragged = false
    private var lastDraggedForPID: pid_t?

    private var ignoredWords: Set<String> = []
    private let ignoredWordsURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ghostedit/ignored_words.json")
    }()

    // Model-based feedback
    private var modelDebounceTimer: Timer?
    private var modelCheckInProgress = false
    private var lastModelCheckedText: String?
    private var modelCheckGeneration: UInt64 = 0
    private weak var configManagerRef: ConfigManager?
    private var localModelRunnerRef: LocalModelRunner?
    static let modelDebounceInterval: TimeInterval = 2.5

    init(configManager: ConfigManager? = nil, localModelRunner: LocalModelRunner? = nil) {
        self.configManagerRef = configManager
        self.localModelRunnerRef = localModelRunner
    }

    // MARK: - Lifecycle

    func start() {
        loadIgnoredWords()
        state = .idle
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: LiveFeedbackSupport.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.schedulePoll()
        }

        // Pre-warm local model if configured
        if let configManager = configManagerRef {
            let config = configManager.loadConfig()
            if !config.localModelRepoID.isEmpty, let runner = localModelRunnerRef {
                let modelPath = LocalModelSupport.modelDirectoryURL(
                    baseDirectoryURL: configManager.baseDirectoryURL,
                    repoID: config.localModelRepoID
                ).path
                let pythonPath = config.localModelPythonPath.isEmpty
                    ? PythonEnvironmentSupport.detectPythonPath(homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)
                    : config.localModelPythonPath
                let promptTemplate = LocalModelSupport.resolvedPromptTemplate(for: config.localModelRepoID, config: config)
                backgroundQueue.async {
                    _ = try? runner.correctText(
                        "Hello.",
                        modelPath: modelPath,
                        pythonPath: pythonPath,
                        timeoutSeconds: 30,
                        promptTemplate: promptTemplate
                    )
                }
            }
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        modelDebounceTimer?.invalidate()
        modelDebounceTimer = nil
        popoverDismissTimer?.invalidate()
        popoverDismissTimer = nil
        dismissWidget()
        dismissPopover()
        lastCheckedText = nil
        currentCheckedText = nil
        lastModelCheckedText = nil
        currentIssues = []
        currentFocusedPID = nil
        state = .idle
        isPolling = false
        isMouseInsidePopover = false
        modelCheckInProgress = false
        modelCheckGeneration &+= 1
    }

    // MARK: - Polling

    private func schedulePoll() {
        // Re-entrancy guard: skip if previous poll is still running
        guard !isPolling else { return }
        isPolling = true

        backgroundQueue.async { [weak self] in
            self?.pollFocusedTextField()
        }
    }

    private func pollFocusedTextField() {
        defer { isPolling = false }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            DispatchQueue.main.async { [weak self] in self?.dismissWidget() }
            return
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusResult == .success, let focused = focusedValue else {
            DispatchQueue.main.async { [weak self] in self?.dismissWidget() }
            return
        }

        let element = focused as! AXUIElement

        // Check if it's a text element
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        guard role == kAXTextAreaRole || role == kAXTextFieldRole else {
            DispatchQueue.main.async { [weak self] in self?.dismissWidget() }
            return
        }

        // Read text value
        var textValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        guard let text = textValue as? String, !text.isEmpty else {
            DispatchQueue.main.async { [weak self] in self?.dismissWidget() }
            return
        }

        // Debounce: only recheck if text changed
        if text == lastCheckedText {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentFocusedPID = pid
            self?.currentCheckedText = text
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(
                withTimeInterval: SpellCheckSupport.debounceInterval,
                repeats: false
            ) { [weak self] _ in
                self?.triggerCheck(text, element: element)
            }
        }
    }

    // MARK: - Spell Check

    private func triggerCheck(_ text: String, element: AXUIElement) {
        updateState(.checking)

        backgroundQueue.async { [weak self] in
            let issues = self?.performSpellCheck(text) ?? []
            DispatchQueue.main.async { [weak self] in
                self?.lastCheckedText = text
                self?.applyResults(issues, element: element)
                self?.scheduleModelCheck(text, element: element)
            }
        }
    }

    private func performSpellCheck(_ text: String) -> [SpellCheckIssue] {
        guard SpellCheckSupport.shouldCheck(text: text) else {
            return []
        }

        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        var issues: [SpellCheckIssue] = []

        // Use the full check method to detect spelling, grammar, punctuation, and style
        let checkingTypes: NSTextCheckingTypes =
            NSTextCheckingResult.CheckingType.spelling.rawValue |
            NSTextCheckingResult.CheckingType.grammar.rawValue |
            NSTextCheckingResult.CheckingType.correction.rawValue |
            NSTextCheckingResult.CheckingType.quote.rawValue |
            NSTextCheckingResult.CheckingType.dash.rawValue |
            NSTextCheckingResult.CheckingType.replacement.rawValue

        let results = checker.check(
            text,
            range: NSRange(location: 0, length: nsText.length),
            types: checkingTypes,
            options: nil,
            inSpellDocumentWithTag: 0,
            orthography: nil,
            wordCount: nil
        )

        for result in results {
            if issues.count >= SpellCheckSupport.maxDisplayIssues { break }

            switch result.resultType {
            case .spelling:
                let word = nsText.substring(with: result.range)
                let guesses = checker.guesses(
                    forWordRange: result.range,
                    in: text,
                    language: nil,
                    inSpellDocumentWithTag: 0
                ) ?? []
                issues.append(SpellCheckIssue(
                    word: word,
                    range: result.range,
                    kind: .spelling,
                    suggestions: guesses
                ))

            case .grammar:
                // Each grammar result can contain multiple detail entries
                for detail in (result.grammarDetails ?? []) {
                    if issues.count >= SpellCheckSupport.maxDisplayIssues { break }

                    let detailRange: NSRange
                    if let rangeValue = detail["NSGrammarRange"] as? NSValue {
                        detailRange = rangeValue.rangeValue
                    } else {
                        detailRange = result.range
                    }

                    // Validate range bounds
                    guard detailRange.location + detailRange.length <= nsText.length else { continue }

                    let word = nsText.substring(with: detailRange)
                    let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                    issues.append(SpellCheckIssue(
                        word: word,
                        range: detailRange,
                        kind: .grammar,
                        suggestions: corrections
                    ))
                }

            case .correction:
                // Autocorrect-style suggestions
                if let replacement = result.replacementString {
                    let word = nsText.substring(with: result.range)
                    issues.append(SpellCheckIssue(
                        word: word,
                        range: result.range,
                        kind: .spelling,
                        suggestions: [replacement]
                    ))
                }

            case .quote, .dash, .replacement:
                // Smart quotes, em-dashes, symbol replacements (e.g. (c) → ©)
                if let replacement = result.replacementString {
                    let word = nsText.substring(with: result.range)
                    issues.append(SpellCheckIssue(
                        word: word,
                        range: result.range,
                        kind: .style,
                        suggestions: [replacement]
                    ))
                }

            default:
                break
            }
        }

        // Merge with Harper for better grammar/style detection
        let harperIssues = HarperLinter.lint(text)
        var merged = harperIssues
        for nsIssue in issues {
            let overlaps = harperIssues.contains { h in
                h.range.intersection(nsIssue.range) != nil
            }
            if !overlaps {
                merged.append(nsIssue)
            }
        }
        // Filter out likely proper nouns (names) and acronyms from spelling issues
        merged = SpellCheckSupport.filterProperNouns(merged, in: text)
        merged = SpellCheckSupport.filterAcronyms(merged)
        // Sort by position for consistent display
        merged.sort { $0.range.location < $1.range.location }

        return merged
    }

    private func applyResults(_ issues: [SpellCheckIssue], element: AXUIElement) {
        let filtered = SpellCheckSupport.filterIssues(issues, ignoredWords: ignoredWords)
        let displayIssues = SpellCheckSupport.truncateForDisplay(filtered)
        currentIssues = displayIssues

        if displayIssues.isEmpty {
            updateState(.clean)
            dismissPopover()
        } else {
            updateState(.issues(displayIssues.count))
        }

        positionWidget(near: element)
    }

    // MARK: - Model-Based Check

    private func scheduleModelCheck(_ text: String, element: AXUIElement) {
        guard let config = configManagerRef?.loadConfig(),
              !config.localModelRepoID.isEmpty,
              localModelRunnerRef != nil else {
            return
        }

        // Skip if text hasn't changed since last model check
        if text == lastModelCheckedText { return }

        modelDebounceTimer?.invalidate()
        modelDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: Self.modelDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.triggerModelCheck(text, element: element)
        }
    }

    private func triggerModelCheck(_ text: String, element: AXUIElement) {
        guard !modelCheckInProgress,
              let configManager = configManagerRef,
              let runner = localModelRunnerRef else {
            return
        }
        let config = configManager.loadConfig()
        guard !config.localModelRepoID.isEmpty else { return }

        modelCheckInProgress = true
        let generation = modelCheckGeneration
        let pythonPath = config.localModelPythonPath.isEmpty
            ? PythonEnvironmentSupport.detectPythonPath(homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)
            : config.localModelPythonPath
        let modelPath = LocalModelSupport.modelDirectoryURL(
            baseDirectoryURL: configManager.baseDirectoryURL,
            repoID: config.localModelRepoID
        ).path
        let promptTemplate = LocalModelSupport.resolvedPromptTemplate(for: config.localModelRepoID, config: config)

        backgroundQueue.async { [weak self] in
            let corrected = try? runner.correctText(
                text,
                modelPath: modelPath,
                pythonPath: pythonPath,
                timeoutSeconds: 30,
                promptTemplate: promptTemplate
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.modelCheckInProgress = false

                // Discard stale results
                guard generation == self.modelCheckGeneration,
                      text == self.lastCheckedText else {
                    return
                }

                self.lastModelCheckedText = text

                guard let corrected, corrected != text else { return }

                let modelIssues = Self.extractIssuesFromDiff(original: text, corrected: corrected)
                if !modelIssues.isEmpty {
                    self.mergeModelIssues(modelIssues, element: element)
                }
            }
        }
    }

    static func extractIssuesFromDiff(original: String, corrected: String) -> [SpellCheckIssue] {
        let segments = DiffSupport.wordDiff(old: original, new: corrected)
        var issues: [SpellCheckIssue] = []
        let nsOriginal = original as NSString
        var scanOffset = 0

        var i = 0
        while i < segments.count {
            let seg = segments[i]

            if seg.kind == .deletion {
                // Find matching range in original
                let searchRange = NSRange(location: scanOffset, length: nsOriginal.length - scanOffset)
                let foundRange = nsOriginal.range(of: seg.text, range: searchRange)
                guard foundRange.location != NSNotFound else {
                    i += 1
                    continue
                }

                // Check if next segment is an insertion (replacement pair)
                var suggestion = ""
                if i + 1 < segments.count && segments[i + 1].kind == .insertion {
                    suggestion = segments[i + 1].text
                    i += 1
                }

                if !suggestion.isEmpty {
                    issues.append(SpellCheckIssue(
                        word: seg.text,
                        range: foundRange,
                        kind: .grammar,
                        suggestions: [suggestion]
                    ))
                }

                scanOffset = foundRange.location + foundRange.length
            } else if seg.kind == .equal {
                // Advance scan offset past equal text
                let searchRange = NSRange(location: scanOffset, length: nsOriginal.length - scanOffset)
                let foundRange = nsOriginal.range(of: seg.text, range: searchRange)
                if foundRange.location != NSNotFound {
                    scanOffset = foundRange.location + foundRange.length
                }
            }

            i += 1
        }

        return issues
    }

    private func mergeModelIssues(_ modelIssues: [SpellCheckIssue], element: AXUIElement) {
        var merged = currentIssues
        for issue in modelIssues {
            let overlaps = merged.contains { existing in
                existing.range.intersection(issue.range) != nil
            }
            if !overlaps {
                merged.append(issue)
            }
        }
        merged.sort { $0.range.location < $1.range.location }

        let filtered = SpellCheckSupport.filterIssues(merged, ignoredWords: ignoredWords)
        let displayIssues = SpellCheckSupport.truncateForDisplay(filtered)
        currentIssues = displayIssues

        if displayIssues.isEmpty {
            updateState(.clean)
            dismissPopover()
        } else {
            updateState(.issues(displayIssues.count))
        }

        positionWidget(near: element)
    }

    // MARK: - State

    private func updateState(_ newState: LiveFeedbackState) {
        state = newState
        updateWidgetAppearance()

        if let delay = LiveFeedbackSupport.autoDismissDelay(for: newState) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.state == newState else { return }
                self.dismissWidget()
            }
        }
    }

    // MARK: - Widget

    private func showWidget() {
        guard widgetWindow == nil else { return }

        let size = LiveFeedbackSupport.widgetWidth // Square widget

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let container = DraggableWidgetView(frame: window.contentView!.bounds)
        container.onClick = { [weak self] in self?.widgetClicked() }
        container.onDrag = { [weak self] in
            self?.widgetManuallyDragged = true
            self?.repositionPopover()
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        container.layer?.cornerRadius = LiveFeedbackSupport.widgetCornerRadius
        container.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        container.layer?.shadowOffset = CGSize(width: 0, height: -1)
        container.layer?.shadowRadius = 4
        container.layer?.shadowOpacity = 1.0
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        // App icon in the center
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = LiveFeedbackSupport.widgetIconSize / 2
        iconView.layer?.masksToBounds = true

        // Status dot indicator (bottom-right corner of the icon)
        let dotSize = LiveFeedbackSupport.widgetDotSize
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        dot.layer?.borderWidth = 1.5
        dot.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(dot)
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            container.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            container.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: LiveFeedbackSupport.widgetIconSize),
            iconView.heightAnchor.constraint(equalToConstant: LiveFeedbackSupport.widgetIconSize),

            dot.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
            dot.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: LiveFeedbackSupport.widgetDotOffset),
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
        ])

        self.widgetWindow = window
        self.widgetIconView = iconView
        self.widgetDot = dot

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = TimeInterval(LiveFeedbackSupport.widgetFadeInDuration)
            window.animator().alphaValue = 1
        }

    }

    private func widgetClicked() {
        if popoverPanel?.isVisible == true {
            dismissPopover()
        } else {
            showPopover()
        }
    }

    private func dismissWidget() {
        guard let window = widgetWindow else { return }
        dismissPopover()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = TimeInterval(LiveFeedbackSupport.widgetFadeOutDuration)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.widgetWindow = nil
            self?.widgetIconView = nil
            self?.widgetDot = nil
        })
    }

    private func updateWidgetAppearance() {
        guard widgetWindow != nil else {
            if state != .idle {
                showWidget()
            }
            return
        }

        let colorName = LiveFeedbackSupport.statusColorName(for: state)
        let dotColor: NSColor
        switch colorName {
        case "systemOrange": dotColor = .systemOrange
        case "systemGreen": dotColor = .systemGreen
        case "systemRed": dotColor = .systemRed
        default: dotColor = .systemGray
        }

        // Animate the dot color change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            widgetDot?.layer?.backgroundColor = dotColor.cgColor
        }
    }

    private func positionWidget(near element: AXUIElement) {
        if widgetWindow == nil {
            showWidget()
        }

        // Reset drag flag when focused app changes
        if let pid = currentFocusedPID, pid != lastDraggedForPID {
            widgetManuallyDragged = false
        }
        if widgetManuallyDragged {
            lastDraggedForPID = currentFocusedPID
            return
        }

        // Try to get bounds of the focused element to position the widget below it
        var boundsValue: AnyObject?
        let boundsResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &boundsValue
        )

        var sizeValue: AnyObject?
        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard boundsResult == .success, sizeResult == .success,
              let posValue = boundsValue, let szValue = sizeValue else {
            // Fallback: position at bottom-right of screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.maxX - LiveFeedbackSupport.widgetWidth - 20
                let y = screenFrame.minY + 20
                widgetWindow?.setFrameOrigin(NSPoint(x: x, y: y))
            }
            return
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(szValue as! AXValue, .cgSize, &size)

        // Convert from top-left screen coords to Cocoa bottom-left coords
        // Position widget BELOW the text field (outside), not overlapping it
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            let widgetX = position.x + size.width - LiveFeedbackSupport.widgetWidth
            let fieldBottomY = screenHeight - (position.y + size.height)
            let widgetY = fieldBottomY - LiveFeedbackSupport.widgetHeight - 8

            // If no space below, position above the text field instead
            let finalY: CGFloat
            if widgetY < screen.visibleFrame.minY {
                finalY = screenHeight - position.y + 8
            } else {
                finalY = widgetY
            }

            widgetWindow?.setFrameOrigin(NSPoint(x: max(0, widgetX), y: max(0, finalY)))
        }
    }

    // MARK: - Popover

    private func showPopover() {
        guard !currentIssues.isEmpty, let widgetFrame = widgetWindow?.frame else { return }

        dismissPopover()

        let fixableCount = currentIssues.filter { !$0.suggestions.isEmpty }.count
        let hintHeight: CGFloat = fixableCount > 0 ? 26 : 0
        let height = LiveFeedbackSupport.popoverHeight(for: currentIssues.count) + hintHeight
        let popoverWidth = LiveFeedbackSupport.popoverWidth
        var popoverX = widgetFrame.origin.x
        var popoverY = widgetFrame.origin.y + widgetFrame.height + 4

        // Smart positioning: clamp to screen bounds
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            // Vertical: if popover overflows top, place below widget
            if popoverY + height > visibleFrame.maxY {
                popoverY = widgetFrame.origin.y - height - 4
            }
            // Horizontal: clamp so popover doesn't go off the right or left edge
            if popoverX + popoverWidth > visibleFrame.maxX {
                popoverX = visibleFrame.maxX - popoverWidth
            }
            if popoverX < visibleFrame.minX {
                popoverX = visibleFrame.minX
            }
        }

        let panel = NSPanel(
            contentRect: NSRect(
                x: popoverX,
                y: popoverY,
                width: popoverWidth,
                height: height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let trackingView = PopoverTrackingView(frame: panel.contentView!.bounds)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in
            self?.isMouseInsidePopover = true
        }
        trackingView.onMouseExited = { [weak self] in
            self?.isMouseInsidePopover = false
        }

        let container = NSView(frame: trackingView.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = LiveFeedbackSupport.popoverCornerRadius
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let displayIssues = Array(currentIssues.prefix(LiveFeedbackSupport.popoverMaxVisibleRows))
        for (index, issue) in displayIssues.enumerated() {
            let row = makeIssueRow(issue, index: index)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: LiveFeedbackSupport.popoverWidth - LiveFeedbackSupport.popoverPadding * 2).isActive = true

            // Add separator between rows
            if index < displayIssues.count - 1 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalToConstant: LiveFeedbackSupport.popoverWidth - LiveFeedbackSupport.popoverPadding * 2).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: LiveFeedbackSupport.popoverPadding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LiveFeedbackSupport.popoverPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LiveFeedbackSupport.popoverPadding),
        ])

        // "Fix All" button at the bottom
        if fixableCount > 0 {
            let btnSeparator = NSView()
            btnSeparator.wantsLayer = true
            btnSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
            btnSeparator.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(btnSeparator)
            btnSeparator.widthAnchor.constraint(equalToConstant: popoverWidth - LiveFeedbackSupport.popoverPadding * 2).isActive = true
            btnSeparator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

            let fixAllButton = NSButton(title: "Fix All (\(fixableCount))", target: self, action: #selector(fixAllButtonClicked))
            fixAllButton.bezelStyle = .recessed
            fixAllButton.controlSize = .small
            fixAllButton.font = .systemFont(ofSize: 11, weight: .medium)
            fixAllButton.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(fixAllButton)
            fixAllButton.widthAnchor.constraint(equalToConstant: popoverWidth - LiveFeedbackSupport.popoverPadding * 2).isActive = true
            fixAllButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        trackingView.addSubview(container)
        panel.contentView!.addSubview(trackingView)
        panel.orderFrontRegardless()
        self.popoverPanel = panel
    }

    private func refreshPopoverContent() {
        if currentIssues.isEmpty {
            dismissPopover()
        } else if popoverPanel?.isVisible == true {
            showPopover()
        }
    }

    private func dismissPopover() {
        popoverDismissTimer?.invalidate()
        popoverDismissTimer = nil
        isMouseInsidePopover = false
        popoverPanel?.orderOut(nil)
        popoverPanel = nil
    }

    private func repositionPopover() {
        guard let popover = popoverPanel, popover.isVisible,
              let widgetFrame = widgetWindow?.frame else { return }

        let popoverSize = popover.frame.size
        var popoverX = widgetFrame.origin.x
        var popoverY = widgetFrame.origin.y + widgetFrame.height + 4

        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            if popoverY + popoverSize.height > visibleFrame.maxY {
                popoverY = widgetFrame.origin.y - popoverSize.height - 4
            }
            if popoverX + popoverSize.width > visibleFrame.maxX {
                popoverX = visibleFrame.maxX - popoverSize.width
            }
            if popoverX < visibleFrame.minX {
                popoverX = visibleFrame.minX
            }
        }

        popover.setFrameOrigin(NSPoint(x: popoverX, y: popoverY))
    }

    private func makeIssueRow(_ issue: SpellCheckIssue, index: Int) -> NSView {
        let hasSuggestion = !issue.suggestions.isEmpty
        let row = IssueRowView(index: index, clickable: true)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: LiveFeedbackSupport.popoverRowHeight).isActive = true

        // Icon
        let iconName = SpellCheckSupport.iconName(for: issue.kind)
        let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: issue.kind.rawValue)
        let iconView = NSImageView(image: iconImage ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = iconTintColor(for: issue.kind)

        // Top row: word (and optional arrow + suggestion)
        let wordLabel = NSTextField(labelWithString: issue.word)
        wordLabel.font = .systemFont(ofSize: 13, weight: .medium)
        wordLabel.textColor = .labelColor
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        // Kind label
        let kindLabel = NSTextField(labelWithString: issue.kind.rawValue.capitalized)
        kindLabel.font = .systemFont(ofSize: 10)
        kindLabel.textColor = .tertiaryLabelColor
        kindLabel.translatesAutoresizingMaskIntoConstraints = false

        // Action buttons (right-aligned)
        let btnSize = LiveFeedbackSupport.issueActionButtonSize
        let btnSpacing = LiveFeedbackSupport.issueActionButtonSpacing

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = btnSpacing
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        // Accept button (checkmark) — only if suggestion available
        if hasSuggestion {
            let acceptBtn = makeActionButton(
                symbolName: "checkmark.circle.fill",
                tintColor: .systemGreen,
                tag: index,
                action: #selector(acceptButtonClicked(_:)),
                tooltip: "Apply fix"
            )
            buttonStack.addArrangedSubview(acceptBtn)
        }

        // Ignore once (X mark)
        let ignoreOnceBtn = makeActionButton(
            symbolName: "xmark.circle",
            tintColor: .secondaryLabelColor,
            tag: index,
            action: #selector(ignoreOnceButtonClicked(_:)),
            tooltip: "Ignore once"
        )
        buttonStack.addArrangedSubview(ignoreOnceBtn)

        // Ignore always (slash circle)
        let ignoreAlwaysBtn = makeActionButton(
            symbolName: "nosign",
            tintColor: .secondaryLabelColor,
            tag: index,
            action: #selector(ignoreAlwaysButtonClicked(_:)),
            tooltip: "Always ignore"
        )
        buttonStack.addArrangedSubview(ignoreAlwaysBtn)

        row.addSubview(iconView)
        row.addSubview(wordLabel)
        row.addSubview(kindLabel)
        row.addSubview(buttonStack)

        var constraints = [
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: LiveFeedbackSupport.popoverRowIconSize),
            iconView.heightAnchor.constraint(equalToConstant: LiveFeedbackSupport.popoverRowIconSize),

            kindLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -LiveFeedbackSupport.popoverRowVerticalPadding),
            kindLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: LiveFeedbackSupport.popoverRowIconPadding),

            buttonStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: btnSize),
        ]

        if hasSuggestion {
            let arrowLabel = NSTextField(labelWithString: "\u{2192}")
            arrowLabel.font = .systemFont(ofSize: 12)
            arrowLabel.textColor = .secondaryLabelColor
            arrowLabel.translatesAutoresizingMaskIntoConstraints = false

            let suggestionLabel = NSTextField(labelWithString: issue.suggestions[0])
            suggestionLabel.font = .systemFont(ofSize: 13, weight: .medium)
            suggestionLabel.textColor = .systemGreen
            suggestionLabel.lineBreakMode = .byTruncatingTail
            suggestionLabel.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(arrowLabel)
            row.addSubview(suggestionLabel)

            constraints.append(contentsOf: [
                wordLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: LiveFeedbackSupport.popoverRowVerticalPadding),
                wordLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: LiveFeedbackSupport.popoverRowIconPadding),

                arrowLabel.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
                arrowLabel.leadingAnchor.constraint(equalTo: wordLabel.trailingAnchor, constant: LiveFeedbackSupport.popoverRowArrowPadding),

                suggestionLabel.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
                suggestionLabel.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: LiveFeedbackSupport.popoverRowArrowPadding),
                suggestionLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -btnSpacing),
            ])
        } else {
            constraints.append(contentsOf: [
                wordLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: LiveFeedbackSupport.popoverRowVerticalPadding),
                wordLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: LiveFeedbackSupport.popoverRowIconPadding),
                wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -btnSpacing),
            ])
        }

        NSLayoutConstraint.activate(constraints)

        return row
    }

    private func makeActionButton(
        symbolName: String,
        tintColor: NSColor,
        tag: Int,
        action: Selector,
        tooltip: String
    ) -> NSButton {
        let btnSize = LiveFeedbackSupport.issueActionButtonSize
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: btnSize, height: btnSize))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.tag = tag
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: btnSize).isActive = true
        btn.heightAnchor.constraint(equalToConstant: btnSize).isActive = true

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            btn.image = img
            btn.contentTintColor = tintColor
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleProportionallyDown
        }

        return btn
    }

    private func iconTintColor(for kind: SpellCheckIssue.Kind) -> NSColor {
        switch kind {
        case .spelling: return .systemRed
        case .grammar: return .systemOrange
        case .style: return .systemBlue
        }
    }

    @objc private func issueRowClicked(_ gesture: NSClickGestureRecognizer) {
        guard let rowView = gesture.view as? IssueRowView else { return }
        let index = rowView.index
        guard index < currentIssues.count else { return }
        let issue = currentIssues[index]
        guard let replacement = issue.suggestions.first else { return }
        applyFix(issue: issue, replacement: replacement, fixedIndex: index)
    }

    private func applyFix(issue: SpellCheckIssue, replacement: String, fixedIndex: Int) {
        guard let pid = currentFocusedPID else { return }

        // Get the focused element directly — do NOT re-query later,
        // because clicking the popover row may shift AX focus.
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        )
        guard focusResult == .success, let focused = focusedValue else { return }
        let element = focused as! AXUIElement

        var textValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        guard let currentText = textValue as? String else { return }

        let nsText = currentText as NSString
        let range = issue.range

        // Bounds check
        guard range.location + range.length <= nsText.length else {
            triggerRecheck()
            return
        }

        // Verify word still matches
        let wordAtRange = nsText.substring(with: range)
        guard wordAtRange == issue.word else {
            triggerRecheck()
            return
        }

        // Replace directly in the full text and set via kAXValueAttribute.
        // This is more reliable than the two-step range-select + set-selected-text
        // approach, which can fail when AX focus shifts after clicking the popover.
        let newText = nsText.replacingCharacters(in: range, with: replacement)
        let setResult = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, newText as CFTypeRef
        )

        if setResult == .success {
            // Re-query focused element and place cursor right after the replacement
            let cursorPos = range.location + (replacement as NSString).length
            var freshFocused: AnyObject?
            if AXUIElementCopyAttributeValue(
                appElement, kAXFocusedUIElementAttribute as CFString, &freshFocused
            ) == .success, let fresh = freshFocused {
                let freshElement = fresh as! AXUIElement
                var cursorRange = CFRange(location: cursorPos, length: 0)
                if let cursorValue = AXValueCreate(.cfRange, &cursorRange) {
                    AXUIElementSetAttributeValue(
                        freshElement, kAXSelectedTextRangeAttribute as CFString, cursorValue
                    )
                }
            }

            adjustIssuesAfterFix(
                fixedIndex: fixedIndex,
                originalRange: range,
                replacementLength: (replacement as NSString).length
            )
            refreshPopoverContent()
        }
    }

    private func adjustIssuesAfterFix(fixedIndex: Int, originalRange: NSRange, replacementLength: Int) {
        let lengthDelta = replacementLength - originalRange.length

        var updated: [SpellCheckIssue] = []
        for (i, issue) in currentIssues.enumerated() {
            if i == fixedIndex { continue }
            if issue.range.location >= originalRange.location + originalRange.length {
                // Shift subsequent issues by the length delta
                let newRange = NSRange(
                    location: issue.range.location + lengthDelta,
                    length: issue.range.length
                )
                updated.append(SpellCheckIssue(
                    word: issue.word,
                    range: newRange,
                    kind: issue.kind,
                    suggestions: issue.suggestions
                ))
            } else {
                updated.append(issue)
            }
        }

        currentIssues = updated
        if currentIssues.isEmpty {
            updateState(.clean)
        } else {
            updateState(.issues(currentIssues.count))
        }

        // Clear cached text so next poll rechecks
        lastCheckedText = nil
        currentCheckedText = nil
    }

    private func triggerRecheck() {
        lastCheckedText = nil
        currentCheckedText = nil
    }

    // MARK: - Fix All

    @objc private func fixAllButtonClicked() {
        applyAllFixes()
    }

    @discardableResult
    func applyAllFixes() -> (original: String, fixed: String)? {
        guard let pid = currentFocusedPID else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        )
        guard focusResult == .success, let focused = focusedValue else { return nil }
        let element = focused as! AXUIElement

        var textValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        guard let currentText = textValue as? String else { return nil }

        // Save cursor position
        var cursorLocation = (currentText as NSString).length
        var rangeValue: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let axValue = rangeValue {
            var savedRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(axValue as! AXValue, .cfRange, &savedRange) {
                cursorLocation = savedRange.location
            }
        }

        // Apply all fixable issues from last to first so earlier ranges stay valid
        let fixableIssues = currentIssues
            .enumerated()
            .filter { !$0.element.suggestions.isEmpty }
            .sorted { $0.element.range.location > $1.element.range.location }

        var nsText = currentText as NSString
        var cursorDelta = 0
        for (_, issue) in fixableIssues {
            let range = issue.range
            guard range.location + range.length <= nsText.length else { continue }
            let wordAtRange = nsText.substring(with: range)
            guard wordAtRange == issue.word else { continue }
            guard let replacement = issue.suggestions.first else { continue }
            nsText = nsText.replacingCharacters(in: range, with: replacement) as NSString
            if range.location < cursorLocation {
                cursorDelta += (replacement as NSString).length - range.length
            }
        }

        let setResult = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, nsText as CFTypeRef
        )

        if setResult == .success {
            // Re-query the focused element (some apps invalidate after text changes)
            // and restore cursor position adjusted for length changes
            let newCursorPos = max(0, min(cursorLocation + cursorDelta, nsText.length))
            var freshFocused: AnyObject?
            if AXUIElementCopyAttributeValue(
                appElement, kAXFocusedUIElementAttribute as CFString, &freshFocused
            ) == .success, let fresh = freshFocused {
                let freshElement = fresh as! AXUIElement
                var restoredRange = CFRange(location: newCursorPos, length: 0)
                if let cursorValue = AXValueCreate(.cfRange, &restoredRange) {
                    AXUIElementSetAttributeValue(
                        freshElement, kAXSelectedTextRangeAttribute as CFString, cursorValue
                    )
                }
            }

            // Remove all fixed issues, keep only those without suggestions
            currentIssues = currentIssues.filter { $0.suggestions.isEmpty }

            if currentIssues.isEmpty {
                updateState(.clean)
            } else {
                updateState(.issues(currentIssues.count))
            }

            lastCheckedText = nil
            currentCheckedText = nil
            refreshPopoverContent()

            let fixedText = nsText as String
            if fixedText != currentText {
                return (original: currentText, fixed: fixedText)
            }
        }
        return nil
    }

    // MARK: - Ignored Words

    private func loadIgnoredWords() {
        guard let data = try? Data(contentsOf: ignoredWordsURL),
              let words = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        ignoredWords = Set(words)
    }

    private func saveIgnoredWords() {
        let sorted = ignoredWords.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: ignoredWordsURL, options: .atomic)
    }

    private func ignoreOnce(at index: Int) {
        guard index < currentIssues.count else { return }
        currentIssues.remove(at: index)
        if currentIssues.isEmpty {
            updateState(.clean)
        } else {
            updateState(.issues(currentIssues.count))
        }
        lastCheckedText = nil
        currentCheckedText = nil
        refreshPopoverContent()
    }

    private func ignoreAlways(at index: Int) {
        guard index < currentIssues.count else { return }
        let word = currentIssues[index].word.lowercased()
        ignoredWords.insert(word)
        saveIgnoredWords()
        // Remove all issues matching this word
        currentIssues = SpellCheckSupport.filterIssues(currentIssues, ignoredWords: ignoredWords)
        if currentIssues.isEmpty {
            updateState(.clean)
        } else {
            updateState(.issues(currentIssues.count))
        }
        lastCheckedText = nil
        currentCheckedText = nil
        refreshPopoverContent()
    }

    @objc private func acceptButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < currentIssues.count else { return }
        let issue = currentIssues[index]
        guard let replacement = issue.suggestions.first else { return }
        applyFix(issue: issue, replacement: replacement, fixedIndex: index)
    }

    @objc private func ignoreOnceButtonClicked(_ sender: NSButton) {
        ignoreOnce(at: sender.tag)
    }

    @objc private func ignoreAlwaysButtonClicked(_ sender: NSButton) {
        ignoreAlways(at: sender.tag)
    }

    // MARK: - Inner Classes

    private final class DraggableWidgetView: NSView {
        var onClick: (() -> Void)?
        var onDrag: (() -> Void)?
        private var dragOrigin: NSPoint?
        private var wasDragged = false

        override func mouseDown(with event: NSEvent) {
            dragOrigin = event.locationInWindow
            wasDragged = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin = dragOrigin, let window = self.window else { return }
            let current = event.locationInWindow
            let dx = current.x - origin.x
            let dy = current.y - origin.y
            if !wasDragged && (abs(dx) + abs(dy)) < 3 { return }
            wasDragged = true
            var frame = window.frame
            frame.origin.x += dx
            frame.origin.y += dy
            window.setFrameOrigin(frame.origin)
            onDrag?()
        }

        override func mouseUp(with event: NSEvent) {
            if !wasDragged {
                onClick?()
            }
            dragOrigin = nil
            wasDragged = false
        }
    }

    private final class PopoverTrackingView: NSView {
        var onMouseEntered: (() -> Void)?
        var onMouseExited: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        override func mouseEntered(with event: NSEvent) {
            onMouseEntered?()
        }

        override func mouseExited(with event: NSEvent) {
            onMouseExited?()
        }
    }

    private final class IssueRowView: NSView {
        let index: Int
        private let clickable: Bool
        private var trackingArea: NSTrackingArea?
        private var hoverLayer: CALayer?

        init(index: Int, clickable: Bool) {
            self.index = index
            self.clickable = clickable
            super.init(frame: .zero)
            wantsLayer = true
            setupHoverLayer()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupHoverLayer() {
            let hover = CALayer()
            hover.backgroundColor = NSColor.labelColor.withAlphaComponent(
                LiveFeedbackSupport.popoverRowHoverAlpha
            ).cgColor
            hover.cornerRadius = 4
            hover.isHidden = true
            layer?.addSublayer(hover)
            hoverLayer = hover
        }

        override func layout() {
            super.layout()
            hoverLayer?.frame = bounds
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area = trackingArea {
                removeTrackingArea(area)
            }
            guard clickable else { return }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            hoverLayer?.isHidden = false
            NSCursor.pointingHand.push()
        }

        override func mouseExited(with event: NSEvent) {
            hoverLayer?.isHidden = true
            NSCursor.pop()
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            if clickable {
                addCursorRect(bounds, cursor: .pointingHand)
            }
        }
    }
}
