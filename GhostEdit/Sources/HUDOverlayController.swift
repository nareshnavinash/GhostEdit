import AppKit

final class HUDOverlayController {
    private var panel: NSPanel?
    private var effectView: NSVisualEffectView?
    private var tintOverlay: NSView?
    private var spinner: NSProgressIndicator?
    private var ghostImageView: NSImageView?
    private var messageLabel: NSTextField?
    private var diffLabel: NSTextField?
    private var dismissWorkItem: DispatchWorkItem?
    private var ghostWithSpectacles: NSImage?
    private var ghostWithoutSpectacles: NSImage?
    private var isDiffMode = false
    private var dismissOverride: TimeInterval?

    func show(state: HUDOverlayState, dismissAfter: TimeInterval? = nil) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        dismissOverride = dismissAfter

        let needsDiff = isDiffState(state)
        if panel == nil || needsDiff != isDiffMode {
            tearDownPanel()
            if needsDiff {
                buildDiffPanel(for: state)
            } else {
                buildPanel()
            }
        }

        applyContent(for: state)

        guard let panel else { return }
        // Start 10px below and faded out, then slide up
        var frame = panel.frame
        frame.origin.y -= 10
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = TimeInterval(HUDOverlaySupport.fadeInDuration)
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var targetFrame = panel.frame
            targetFrame.origin.y += 10
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }

        scheduleAutoDismissIfNeeded(for: state)
    }

    func update(state: HUDOverlayState, dismissAfter: TimeInterval? = nil) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        dismissOverride = dismissAfter

        let needsDiff = isDiffState(state)
        if panel == nil || needsDiff != isDiffMode {
            tearDownPanel()
            if needsDiff {
                buildDiffPanel(for: state)
            } else {
                buildPanel()
            }
        }

        applyContent(for: state)

        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        scheduleAutoDismissIfNeeded(for: state)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let panel else { return }

        let fadeDuration = TimeInterval(HUDOverlaySupport.fadeOutDuration)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + 0.05) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        }
    }

    private func isDiffState(_ state: HUDOverlayState) -> Bool {
        if case .successWithDiff = state { return true }
        return false
    }

    private func tearDownPanel() {
        panel?.orderOut(nil)
        panel = nil
        effectView = nil
        tintOverlay = nil
        spinner = nil
        ghostImageView = nil
        messageLabel = nil
        diffLabel = nil
        isDiffMode = false
    }

    private func buildPanel() {
        isDiffMode = false
        let width = HUDOverlaySupport.windowWidth
        let height = HUDOverlaySupport.windowHeight
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let origin = HUDOverlaySupport.windowOrigin(screenSize: screenSize)

        let newPanel = NSPanel(
            contentRect: NSRect(x: origin.x, y: origin.y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        newPanel.isMovableByWindowBackground = false

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effectView.material = .popover
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = HUDOverlaySupport.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.alphaValue = 0.92

        let iconSize = HUDOverlaySupport.iconSize
        let imageView = NSImageView(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = renderGhostImage(size: iconSize, spectacles: true)

        let message = NSTextField(labelWithString: "")
        message.font = NSFont.systemFont(ofSize: HUDOverlaySupport.messageFontSize, weight: .medium)
        message.textColor = .white
        message.alignment = .center
        message.lineBreakMode = .byWordWrapping
        message.maximumNumberOfLines = 2
        message.translatesAutoresizingMaskIntoConstraints = false

        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true

        let stack = NSStackView(views: [imageView, progress, message])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = HUDOverlaySupport.verticalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: iconSize),
            imageView.heightAnchor.constraint(equalToConstant: iconSize),
            stack.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: effectView.leadingAnchor,
                constant: HUDOverlaySupport.contentInset
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: effectView.trailingAnchor,
                constant: -HUDOverlaySupport.contentInset
            ),
        ])

        // Tint overlay for state color
        let tint = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.clear.cgColor
        tint.layer?.cornerRadius = HUDOverlaySupport.cornerRadius
        tint.layer?.masksToBounds = true
        effectView.addSubview(tint, positioned: .below, relativeTo: stack)
        tint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tint.topAnchor.constraint(equalTo: effectView.topAnchor),
            tint.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        newPanel.contentView = effectView

        self.panel = newPanel
        self.effectView = effectView
        self.tintOverlay = tint
        self.spinner = progress
        self.ghostImageView = imageView
        self.messageLabel = message
    }

    private func buildDiffPanel(for state: HUDOverlayState) {
        isDiffMode = true

        guard case .successWithDiff(let segments, let toolsUsed) = state else { return }

        let panelWidth = HUDOverlaySupport.diffWindowWidth
        let inset = HUDOverlaySupport.diffContentInset
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: HUDOverlaySupport.diffWindowMaxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        newPanel.isMovableByWindowBackground = false

        let ev = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: HUDOverlaySupport.diffWindowMaxHeight))
        ev.material = .popover
        ev.state = .active
        ev.blendingMode = .behindWindow
        ev.wantsLayer = true
        ev.layer?.cornerRadius = HUDOverlaySupport.cornerRadius
        ev.layer?.masksToBounds = true
        ev.alphaValue = 0.92

        // Content stack
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // Top row: small ghost + "Done!"
        let iconSize = HUDOverlaySupport.diffIconSize
        let imageView = NSImageView(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = renderGhostImage(size: iconSize, spectacles: false)

        let message = NSTextField(labelWithString: "Done!")
        message.font = NSFont.systemFont(ofSize: HUDOverlaySupport.messageFontSize, weight: .medium)
        message.textColor = .white
        message.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [imageView, message])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: iconSize),
            imageView.heightAnchor.constraint(equalToConstant: iconSize),
        ])

        contentStack.addArrangedSubview(topRow)

        // Tools-used header (if provided)
        if !toolsUsed.isEmpty {
            let toolsLabel = NSTextField(labelWithString: toolsUsed)
            toolsLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
            if let italicDescriptor = toolsLabel.font?.fontDescriptor.withSymbolicTraits(.italic) {
                toolsLabel.font = NSFont(descriptor: italicDescriptor, size: 9)
            }
            toolsLabel.textColor = .secondaryLabelColor
            toolsLabel.translatesAutoresizingMaskIntoConstraints = false

            let pillView = NSView()
            pillView.wantsLayer = true
            pillView.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.1).cgColor
            pillView.layer?.cornerRadius = 4
            pillView.translatesAutoresizingMaskIntoConstraints = false
            pillView.addSubview(toolsLabel)
            NSLayoutConstraint.activate([
                toolsLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 6),
                toolsLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -6),
                toolsLabel.topAnchor.constraint(equalTo: pillView.topAnchor, constant: 2),
                toolsLabel.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -2),
            ])
            contentStack.addArrangedSubview(pillView)
        }

        // Diff text
        let diffField = NSTextField(wrappingLabelWithString: "")
        diffField.isEditable = false
        diffField.isSelectable = false
        diffField.isBezeled = false
        diffField.drawsBackground = false
        diffField.backgroundColor = .clear
        diffField.font = NSFont.systemFont(ofSize: HUDOverlaySupport.diffFontSize)
        diffField.translatesAutoresizingMaskIntoConstraints = false

        let attrString = NSMutableAttributedString()
        for segment in segments {
            switch segment.kind {
            case .equal:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: HUDOverlaySupport.diffFontSize),
                    .foregroundColor: NSColor.labelColor
                ]
                attrString.append(NSAttributedString(string: segment.text, attributes: attrs))
            case .insertion:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: HUDOverlaySupport.diffFontSize),
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                attrString.append(NSAttributedString(string: segment.text, attributes: attrs))
            case .deletion:
                break  // Skip deletions — only show insertions in green
            }
        }
        diffField.attributedStringValue = attrString
        contentStack.addArrangedSubview(diffField)

        ev.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: ev.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: ev.trailingAnchor, constant: -inset),
            contentStack.topAnchor.constraint(equalTo: ev.topAnchor, constant: inset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: ev.bottomAnchor, constant: -inset),
        ])

        // Tint overlay
        let tint = NSView(frame: .zero)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.06).cgColor
        tint.layer?.cornerRadius = HUDOverlaySupport.cornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        ev.addSubview(tint, positioned: .below, relativeTo: contentStack)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
            tint.topAnchor.constraint(equalTo: ev.topAnchor),
            tint.bottomAnchor.constraint(equalTo: ev.bottomAnchor),
        ])

        // Size to fit content
        ev.layoutSubtreeIfNeeded()
        let intrinsicHeight = contentStack.fittingSize.height + inset * 2
        let panelHeight = min(intrinsicHeight, HUDOverlaySupport.diffWindowMaxHeight)

        newPanel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        ev.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        newPanel.contentView = ev

        // Center on screen
        let windowSize = CGSize(width: panelWidth, height: panelHeight)
        let origin = HUDOverlaySupport.windowOrigin(screenSize: screenSize, windowSize: windowSize)
        newPanel.setFrameOrigin(origin)

        // Click to dismiss
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDiffClick))
        ev.addGestureRecognizer(clickGesture)

        self.panel = newPanel
        self.effectView = ev
        self.tintOverlay = tint
        self.ghostImageView = imageView
        self.messageLabel = message
        self.diffLabel = diffField
    }

    @objc private func handleDiffClick() {
        dismiss()
    }

    private func applyContent(for state: HUDOverlayState) {
        // Diff mode content is set up during buildDiffPanel
        if case .successWithDiff = state { return }

        let content = HUDOverlaySupport.content(for: state)
        messageLabel?.stringValue = content.message

        let spectacles = HUDOverlaySupport.showsSpectacles(for: state)
        ghostImageView?.image = renderGhostImage(
            size: HUDOverlaySupport.iconSize,
            spectacles: spectacles
        )

        // Spinner for working state
        if case .working = state {
            spinner?.isHidden = false
            spinner?.startAnimation(nil)
        } else {
            spinner?.stopAnimation(nil)
            spinner?.isHidden = true
        }

        // Color tint per state
        let tintColor: NSColor
        switch state {
        case .working:
            tintColor = NSColor.systemBlue.withAlphaComponent(0.06)
        case .success, .successWithCount:
            tintColor = NSColor.systemGreen.withAlphaComponent(0.06)
        case .successWithDiff:
            tintColor = NSColor.systemGreen.withAlphaComponent(0.06)
        case .fallback:
            tintColor = NSColor.systemOrange.withAlphaComponent(0.06)
        case .error:
            tintColor = NSColor.systemRed.withAlphaComponent(0.06)
        }
        tintOverlay?.layer?.backgroundColor = tintColor.cgColor
    }

    private func scheduleAutoDismissIfNeeded(for state: HUDOverlayState) {
        let delay: TimeInterval
        if let override = dismissOverride {
            delay = override
        } else if let computed = HUDOverlaySupport.autoDismissDelay(for: state) {
            delay = computed
        } else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func renderGhostImage(size: CGFloat, spectacles: Bool) -> NSImage {
        if spectacles, let cached = ghostWithSpectacles { return cached }
        if !spectacles, let cached = ghostWithoutSpectacles { return cached }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let vbX = HUDOverlaySupport.ghostViewBoxOriginX
            let vbY = HUDOverlaySupport.ghostViewBoxOriginY
            let vbSize = HUDOverlaySupport.ghostViewBoxSize
            let scale = size / vbSize

            ctx.translateBy(x: -vbX * scale, y: -vbY * scale)
            ctx.scaleBy(x: scale, y: scale)

            let darkFill = CGColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1)

            // Ghost body
            if let bodyPath = CGPath.from(svgPath: HUDOverlaySupport.ghostBodyPath) {
                ctx.addPath(bodyPath)
                ctx.setFillColor(.white)
                ctx.fillPath()
            }

            // Eyes (rotated ellipses)
            for eye in [HUDOverlaySupport.ghostLeftEye, HUDOverlaySupport.ghostRightEye] {
                ctx.saveGState()
                ctx.translateBy(x: eye.cx, y: eye.cy)
                ctx.rotate(by: eye.rotation * .pi / 180)
                let eyeRect = CGRect(x: -eye.rx, y: -eye.ry, width: eye.rx * 2, height: eye.ry * 2)
                ctx.addEllipse(in: eyeRect)
                ctx.setFillColor(darkFill)
                ctx.fillPath()
                ctx.restoreGState()

                // Highlight
                let hlRect = CGRect(
                    x: eye.highlightCX - eye.highlightR,
                    y: eye.highlightCY - eye.highlightR,
                    width: eye.highlightR * 2,
                    height: eye.highlightR * 2
                )
                ctx.addEllipse(in: hlRect)
                ctx.setFillColor(.white)
                ctx.fillPath()

                // Spectacle lens (only for working state)
                if spectacles {
                    let lensRect = CGRect(
                        x: eye.cx - eye.lensR,
                        y: eye.cy - eye.lensR,
                        width: eye.lensR * 2,
                        height: eye.lensR * 2
                    )
                    ctx.addEllipse(in: lensRect)
                    ctx.setStrokeColor(darkFill)
                    ctx.setLineWidth(HUDOverlaySupport.ghostStrokeWidth)
                    ctx.strokePath()
                }
            }

            // Mouth
            if let mouthPath = CGPath.from(svgPath: HUDOverlaySupport.ghostMouthPath) {
                ctx.addPath(mouthPath)
                ctx.setFillColor(darkFill)
                ctx.fillPath()
            }

            // Spectacle bridge and arms (only for working state)
            if spectacles {
                let sw = HUDOverlaySupport.ghostStrokeWidth
                for pathStr in [HUDOverlaySupport.ghostBridgePath,
                                HUDOverlaySupport.ghostLeftArmPath,
                                HUDOverlaySupport.ghostRightArmPath] {
                    if let p = CGPath.from(svgPath: pathStr) {
                        ctx.addPath(p)
                        ctx.setStrokeColor(darkFill)
                        ctx.setLineWidth(sw)
                        ctx.setLineCap(.round)
                        ctx.strokePath()
                    }
                }
            }

            return true
        }

        if spectacles {
            ghostWithSpectacles = image
        } else {
            ghostWithoutSpectacles = image
        }
        return image
    }
}

private extension CGPath {
    static func from(svgPath: String) -> CGPath? {
        let path = CGMutablePath()
        let scanner = Scanner(string: svgPath)
        scanner.charactersToBeSkipped = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ","))

        var currentCommand: Character = "M"

        while !scanner.isAtEnd {
            if let cmd = scanner.scanCharacter(), "MmLlCcQqZz".contains(cmd) {
                currentCommand = cmd
            }

            switch currentCommand {
            case "M":
                guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                path.move(to: CGPoint(x: x, y: y))
                currentCommand = "L"
            case "L":
                guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                guard let x1 = scanner.scanDouble(), let y1 = scanner.scanDouble(),
                      let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                      let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2)
                )
            case "Q":
                guard let cx = scanner.scanDouble(), let cy = scanner.scanDouble(),
                      let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case "Z", "z":
                path.closeSubpath()
            default:
                _ = scanner.scanDouble()
            }
        }

        return path.isEmpty ? nil : path
    }
}
