import AppKit
import ApplicationServices
import UserNotifications
import UniformTypeIdentifiers

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkeyManager = HotkeyManager()
    private let clipboardManager = ClipboardManager()
    private let configManager = ConfigManager()
    private lazy var historyStore = CorrectionHistoryStore(fileURL: configManager.historyURL)
    private lazy var shellRunner = ShellRunner(configManager: configManager)
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var hudController: HUDOverlayController?

    private var statusMenu: NSMenu?
    private var statusMenuItem: NSMenuItem?
    private var runNowMenuItem: NSMenuItem?
    private var historyMenuItem: NSMenuItem?
    private var writingCoachMenuItem: NSMenuItem?

    private var isProcessing = false
    private var isShowingAccessibilityAlert = false
    private var didShowAccessibilityGuidance = false
    private var clipboardSnapshot: ClipboardManager.Snapshot?
    private var targetAppAtTrigger: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?

    private let statusPrefix = "Status: "
    private let idleMenuBarIcon = MenuBarIconSupport.descriptor(for: .idle)
    private let workingMenuBarIcon = MenuBarIconSupport.descriptor(for: .processing)
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningUnitTests {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        do {
            try configManager.bootstrapIfNeeded()
            try historyStore.bootstrapIfNeeded()
        } catch {
            showFatalAlert(
                title: "GhostEdit Setup Failed",
                message: "Could not create ~/.ghostedit files.\n\n\(error.localizedDescription)"
            )
            return
        }

        startObservingActiveApplication()
        _ = ensureAccessibilityPermission(promptSystemDialog: false, showGuidanceAlert: false)
        syncLaunchAtLoginPreferenceSilently()
        registerHotkey()
        shellRunner.prewarm()
        setStatus("Idle")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        stopProcessingIndicator()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            setMenuBarIcon(idleMenuBarIcon)
            button.toolTip = "GhostEdit"
        }

        let menu = NSMenu()

        let status = NSMenuItem(title: "\(statusPrefix)Idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())

        let runNow = NSMenuItem(
            title: "Fix Selected Text",
            action: #selector(runNowAction),
            keyEquivalent: ""
        )
        runNow.target = self
        menu.addItem(runNow)
        runNowMenuItem = runNow

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let history = NSMenuItem(
            title: "History...",
            action: #selector(openHistoryAction),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)
        historyMenuItem = history

        let writingCoach = NSMenuItem(
            title: "Sharpen My Writing Style",
            action: #selector(openWritingCoachAction),
            keyEquivalent: ""
        )
        writingCoach.target = self
        menu.addItem(writingCoach)
        writingCoachMenuItem = writingCoach

        menu.addItem(.separator())

        let openPrompt = NSMenuItem(
            title: "Open Prompt File",
            action: #selector(openPromptFileAction),
            keyEquivalent: ""
        )
        openPrompt.target = self
        menu.addItem(openPrompt)

        let openConfig = NSMenuItem(
            title: "Open Config File",
            action: #selector(openConfigFileAction),
            keyEquivalent: ""
        )
        openConfig.target = self
        menu.addItem(openConfig)

        let checkAccessibility = NSMenuItem(
            title: "Check Accessibility Permission",
            action: #selector(checkAccessibilityAction),
            keyEquivalent: ""
        )
        checkAccessibility.target = self
        menu.addItem(checkAccessibility)

        menu.addItem(.separator())

        let version = NSMenuItem(title: appVersionText(), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit GhostEdit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusMenu = menu
        statusItem.menu = menu
    }

    private func startObservingActiveApplication() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if let current = NSWorkspace.shared.frontmostApplication {
            cacheExternalAppIfNeeded(current)
        }
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }

        cacheExternalAppIfNeeded(app)
    }

    private func cacheExternalAppIfNeeded(_ app: NSRunningApplication) {
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalActiveApp = app
        }
    }

    private func registerHotkey() {
        let config = configManager.loadConfig()

        hotkeyManager.register(
            keyCode: config.hotkeyKeyCode,
            modifiers: config.hotkeyModifiers
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleHotkeyTrigger()
            }
        }
    }

    @objc private func runNowAction() {
        statusMenu?.cancelTracking()
        handleHotkeyTrigger()
    }

    @objc private func openPromptFileAction() {
        NSWorkspace.shared.open(configManager.promptURL)
    }

    @objc private func openSettingsAction() {
        statusMenu?.cancelTracking()
        showSettingsWindow()
    }

    @objc private func openHistoryAction() {
        statusMenu?.cancelTracking()
        showHistoryWindow()
    }

    @objc private func openWritingCoachAction() {
        statusMenu?.cancelTracking()
        runWritingCoach()
    }

    @objc private func openConfigFileAction() {
        NSWorkspace.shared.open(configManager.configURL)
    }

    @objc private func checkAccessibilityAction() {
        statusMenu?.cancelTracking()
        didShowAccessibilityGuidance = false
        _ = ensureAccessibilityPermission(promptSystemDialog: true, showGuidanceAlert: true)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func handleHotkeyTrigger() {
        guard ensureAccessibilityPermission(promptSystemDialog: false, showGuidanceAlert: true) else {
            NSSound.beep()
            setStatus("Accessibility permission required")
            return
        }

        guard !isProcessing else {
            NSSound.beep()
            setStatus("Already processing")
            return
        }

        guard let targetApp = resolveTargetApplication() else {
            NSSound.beep()
            setStatus("Could not determine target app; focus text app and retry")
            return
        }

        isProcessing = true
        startProcessingIndicator()
        showHUD(state: .working)

        targetAppAtTrigger = targetApp

        // Try accessibility-based reading first (no clipboard round-trip needed).
        if let selectedText = AccessibilityTextSupport.readSelectedText(
            appPID: targetApp.processIdentifier
        ) {
            processSelectedText(selectedText)
            return
        }

        // Fall back to clipboard-based copy.
        clipboardSnapshot = clipboardManager.snapshot()

        let sentinel = "__GHOSTEDIT_SENTINEL_\(UUID().uuidString)__"
        clipboardManager.writePlainText(sentinel)

        let strategies: [ClipboardManager.ShortcutPosting] = [.annotatedSession, .hidSystem]
        attemptCopySelection(sentinel: sentinel, strategies: strategies, index: 0)
    }

    private func resolveTargetApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            return frontmost
        }

        if let cached = lastExternalActiveApp, !cached.isTerminated {
            return cached
        }

        return nil
    }

    private func attemptCopySelection(
        sentinel: String,
        strategies: [ClipboardManager.ShortcutPosting],
        index: Int
    ) {
        guard index < strategies.count else {
            NSSound.beep()
            restoreClipboardSnapshot(after: 0)
            setStatus("No text selected")
            finishProcessing()
            return
        }

        let strategy = strategies[index]
        setStatus("Copying selected text... (\(strategy.displayName))")

        // Give the triggering key chord enough time to release.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            self.targetAppAtTrigger?.activate(options: [.activateAllWindows])

            guard self.clipboardManager.simulateCopyShortcut(using: strategy) else {
                self.attemptCopySelection(sentinel: sentinel, strategies: strategies, index: index + 1)
                return
            }

            self.waitForCopiedText(sentinel: sentinel, timeoutSeconds: 1.4) { [weak self] selectedText in
                guard let self else { return }
                if let selectedText {
                    self.processSelectedText(selectedText)
                    return
                }

                self.attemptCopySelection(sentinel: sentinel, strategies: strategies, index: index + 1)
            }
        }
    }

    private func waitForCopiedText(
        sentinel: String,
        timeoutSeconds: TimeInterval,
        completion: @escaping (String?) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let startTime = Date()

        func poll() {
            if let candidate = clipboardManager.readBestText() {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed != sentinel {
                    completion(trimmed)
                    return
                }
            }

            if Date() >= deadline {
                completion(nil)
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let interval: TimeInterval = elapsed < 0.2 ? 0.02 : 0.06
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: poll)
        }

        poll()
    }

    private func processSelectedText(_ selectedText: String) {
        let prompt: String
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let startedAt = Date()
        do {
            prompt = try configManager.loadPrompt()
        } catch {
            let message = "Could not read prompt file.\n\n\(error.localizedDescription)"
            restoreClipboardSnapshot(after: 0)
            notifyFailure(body: "Correction Failed. \(message)")
            showFailureAlert(title: "Correction Failed", message: message)
            setStatus("Failed to read prompt file")
            finishProcessing()
            return
        }

        let modelDisplay = model.isEmpty ? "provider default" : model
        setStatus("Processing with \(provider.executableName) (\(modelDisplay))...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let correctedText = try self.shellRunner.correctTextPreservingTokens(
                    systemPrompt: prompt,
                    selectedText: selectedText
                )
                self.recordHistoryEntry(
                    originalText: selectedText,
                    generatedText: correctedText,
                    provider: provider,
                    model: model,
                    startedAt: startedAt,
                    succeeded: true
                )

                DispatchQueue.main.async {
                    // Check if target app was terminated during processing.
                    if let targetApp = self.targetAppAtTrigger, targetApp.isTerminated {
                        self.clipboardManager.writePlainText(correctedText)
                        self.clipboardSnapshot = nil
                        self.dismissHUD()
                        self.setStatus("Target app closed; corrected text on clipboard")
                        self.finishProcessing()
                        return
                    }

                    // Try accessibility-based text replacement first (fastest path).
                    // Works on background apps — no focus changes needed.
                    if let targetApp = self.targetAppAtTrigger {
                        let axReplaced = AccessibilityTextSupport.replaceSelectedText(
                            appPID: targetApp.processIdentifier,
                            with: correctedText
                        )
                        if axReplaced {
                            // Verify after a short delay — some apps (e.g. TextEdit) need
                            // time to commit the AX change, while Electron apps (Slack,
                            // Discord, VS Code) accept the call but never actually replace.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                let readBack = AccessibilityTextSupport.readSelectedText(
                                    appPID: targetApp.processIdentifier
                                )
                                if readBack == correctedText {
                                    let time = self.timeFormatter.string(from: Date())
                                    self.setStatus("Last correction succeeded at \(time)")
                                    self.restoreClipboardSnapshot(after: 0)
                                    self.updateHUD(state: .success)
                                    self.finishProcessing()
                                } else {
                                    self.pasteViaClipboard(correctedText: correctedText)
                                }
                            }
                            return
                        }
                    }

                    // AX replacement not available — go straight to clipboard paste.
                    self.pasteViaClipboard(correctedText: correctedText)
                }
            } catch {
                DispatchQueue.main.async {
                    self.restoreClipboardSnapshot(after: 0)
                    self.recordHistoryEntry(
                        originalText: selectedText,
                        generatedText: "",
                        provider: provider,
                        model: model,
                        startedAt: startedAt,
                        succeeded: false
                    )
                    self.handleProcessingError(error)
                    self.dismissHUD()
                    self.finishProcessing()
                }
            }
        }
    }

    private func handleProcessingError(_ error: Error) {
        if case let ShellRunnerError.cliNotFound(provider) = error {
            setStatus("\(provider.executableName) CLI not found; update config.json")
            notifyFailure(body: "Correction Failed. \(provider.displayName) CLI not found.")
            showCLIPathAlert(provider: provider)
            return
        }

        if case let ShellRunnerError.authenticationRequired(provider) = error {
            setStatus("\(provider.executableName) authentication required")
            notifyFailure(body: "Correction Failed. \(provider.displayName) authentication expired. Run `\(provider.authCommand)` in Terminal.")
            showCLIAuthAlert(provider: provider)
            return
        }

        let shouldSuggestModelSwitch: Bool
        if let shellError = error as? ShellRunnerError {
            switch shellError {
            case .processFailed, .timedOut, .emptyResponse:
                shouldSuggestModelSwitch = true
            default:
                shouldSuggestModelSwitch = false
            }
        } else {
            shouldSuggestModelSwitch = false
        }

        let message: String
        if shouldSuggestModelSwitch {
            message = "\(error.localizedDescription)\nTry switching model in Settings if the selected model is busy or unavailable."
        } else {
            message = error.localizedDescription
        }
        setStatus("Correction failed")
        notifyFailure(body: "Correction Failed. \(message)")
        showFailureAlert(title: "Correction Failed", message: message)
    }

    private func startProcessingIndicator() {
        runNowMenuItem?.isEnabled = false
        writingCoachMenuItem?.isEnabled = false
        statusMenu?.cancelTracking()
        statusItem.menu = nil
        setMenuBarIcon(workingMenuBarIcon)
    }

    private func stopProcessingIndicator() {
        runNowMenuItem?.isEnabled = true
        writingCoachMenuItem?.isEnabled = true
        statusItem.menu = statusMenu
        setMenuBarIcon(idleMenuBarIcon)
    }

    private func pasteViaClipboard(correctedText: String) {
        let userCurrentApp = NSWorkspace.shared.frontmostApplication

        if clipboardSnapshot == nil {
            clipboardSnapshot = clipboardManager.snapshot()
        }
        clipboardManager.writePlainText(correctedText)
        targetAppAtTrigger?.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let pasted = self.clipboardManager.simulatePasteShortcut(using: .annotatedSession)
                || self.clipboardManager.simulatePasteShortcut(using: .hidSystem)

            if !pasted {
                NSSound.beep()
                let message = "Could not paste corrected text.\n\nMake sure your cursor is in the target field, then run GhostEdit again."
                self.notifyFailure(body: "Correction Failed. \(message)")
                self.showFailureAlert(title: "Correction Failed", message: message)
                self.setStatus("Paste failed")
                self.dismissHUD()
            } else {
                let time = self.timeFormatter.string(from: Date())
                self.setStatus("Last correction succeeded at \(time)")
                self.updateHUD(state: .success)

                // Restore the user's focus if they switched away from the target app.
                if let userApp = userCurrentApp,
                   let targetApp = self.targetAppAtTrigger,
                   userApp.processIdentifier != targetApp.processIdentifier,
                   !userApp.isTerminated {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                        userApp.activate()
                    }
                }
            }

            self.restoreClipboardSnapshot(after: 0.20)
            self.finishProcessing()
        }
    }

    private func showHUD(state: HUDOverlayState) {
        if hudController == nil {
            hudController = HUDOverlayController()
        }
        hudController?.show(state: state)
    }

    private func updateHUD(state: HUDOverlayState) {
        hudController?.update(state: state)
    }

    private func dismissHUD() {
        hudController?.dismiss()
    }

    private func finishProcessing() {
        isProcessing = false
        targetAppAtTrigger = nil
        stopProcessingIndicator()
    }

    @discardableResult
    private func ensureAccessibilityPermission(
        promptSystemDialog: Bool,
        showGuidanceAlert: Bool
    ) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: promptSystemDialog] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted, showGuidanceAlert, !didShowAccessibilityGuidance {
            didShowAccessibilityGuidance = true
            showAccessibilityAlert()
        }

        return trusted
    }

    private func showAccessibilityAlert() {
        guard !isShowingAccessibilityAlert else {
            return
        }

        isShowingAccessibilityAlert = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = AccessibilitySupport.guidanceText(appName: "GhostEdit")
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Later")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }

            self.isShowingAccessibilityAlert = false
        }
    }

    private func showCLIPathAlert(provider: CLIProvider) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "\(provider.displayName) CLI Not Found"
            alert.informativeText = "Set an absolute path in ~/.ghostedit/config.json (\(provider.configPathKey)), or switch provider/model in Settings."
            alert.addButton(withTitle: "Open Config")
            alert.addButton(withTitle: "OK")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.configManager.configURL)
            }
        }
    }

    private func showCLIAuthAlert(provider: CLIProvider) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "\(provider.displayName) Authentication Required"
            alert.informativeText = "Your \(provider.displayName) CLI session is expired.\n\nRun this command in Terminal:\n\(provider.authCommand)\n\nThen retry GhostEdit."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func notifyFailure(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "GhostEdit"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func setStatus(_ text: String) {
        statusMenuItem?.title = "\(statusPrefix)\(text)"
        statusItem.button?.toolTip = "GhostEdit\n\(text)"
    }

    private func setMenuBarIcon(_ descriptor: MenuBarIconDescriptor) {
        guard let button = statusItem.button else {
            return
        }

        if let iconImage = MenuBarIconSupport.resolveImage(
            named: NSImage.Name(descriptor.assetName)
        ) {
            iconImage.isTemplate = false
            button.image = iconImage
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular)
        ]
        button.image = nil
        button.title = descriptor.fallbackGlyph
        button.attributedTitle = NSAttributedString(string: descriptor.fallbackGlyph, attributes: attrs)
    }

    private func appVersionText() -> String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(shortVersion) (\(build))"
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configManager: configManager
            ) { [weak self] config in
                guard let self else {
                    return
                }
                let provider = config.resolvedProvider
                let model = config.resolvedModel(for: provider)
                let modelDisplay = model.isEmpty ? "provider default" : model
                let hotkeyDisplay = HotkeySupport.displayString(
                    keyCode: config.hotkeyKeyCode,
                    modifiers: config.hotkeyModifiers
                )
                try? self.historyStore.trim(limit: config.historyLimit)
                self.refreshHistoryWindowIfVisible()
                self.registerHotkey()
                self.setStatus("Settings saved (\(provider.executableName), model: \(modelDisplay), hotkey: \(hotkeyDisplay))")
            }
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        refreshHistoryWindowIfVisible()
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func runWritingCoach() {
        guard !isProcessing else {
            NSSound.beep()
            setStatus("Already processing")
            return
        }

        let originalSamples = historyOriginalSamples()
        guard !originalSamples.isEmpty else {
            NSSound.beep()
            setStatus("No history available for writing coach")
            showNoHistoryForWritingCoachAlert()
            return
        }

        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let modelDisplay = model.isEmpty ? "provider default" : model
        let writingInput = WritingCoachSupport.buildInput(from: originalSamples)

        isProcessing = true
        startProcessingIndicator()
        setStatus("Analyzing writing style with \(provider.executableName) (\(modelDisplay))...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let response = try self.shellRunner.correctText(
                    systemPrompt: WritingCoachSupport.systemPrompt,
                    selectedText: writingInput
                )
                let insights = WritingCoachSupport.parseInsights(from: response)

                DispatchQueue.main.async {
                    if let insights {
                        self.showWritingCoachInsights(insights, sampleCount: originalSamples.count)
                    } else {
                        self.showWritingCoachFallback(rawResponse: response, sampleCount: originalSamples.count)
                    }

                    let time = self.timeFormatter.string(from: Date())
                    self.setStatus("Writing coach ready at \(time)")
                    self.finishProcessing()
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleWritingCoachError(error)
                    self.finishProcessing()
                }
            }
        }
    }

    private func historyOriginalSamples() -> [String] {
        historyStore.load().compactMap { entry in
            let trimmed = entry.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func showNoHistoryForWritingCoachAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Sharpen My Writing Style"
        alert.informativeText = "No history samples found yet. Run a few corrections, then try again."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showWritingCoachInsights(_ insights: WritingCoachInsights, sampleCount: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Sharpen My Writing Style"
        alert.informativeText = WritingCoachLayoutSupport.reviewedText(sampleCount: sampleCount)
        alert.accessoryView = buildWritingCoachAccessoryView(insights)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func buildWritingCoachAccessoryView(_ insights: WritingCoachInsights) -> NSView {
        let width = WritingCoachLayoutSupport.accessoryWidth
        let contentWidth = WritingCoachLayoutSupport.panelContentWidth()

        let strengthItems = WritingCoachLayoutSupport.cappedItems(insights.positives)
        let improvementItems = WritingCoachLayoutSupport.cappedItems(insights.improvements)

        let strengthPanel = buildCoachPanel(
            title: "Strengths",
            items: strengthItems,
            prefix: WritingCoachLayoutSupport.strengthPrefix,
            accentColor: .systemGreen,
            contentWidth: contentWidth,
            emptyFallback: WritingCoachLayoutSupport.emptyStrengthsFallback
        )

        let improvementPanel = buildCoachPanel(
            title: "Areas to Improve",
            items: improvementItems,
            prefix: WritingCoachLayoutSupport.improvementPrefix,
            accentColor: .systemPink,
            contentWidth: contentWidth,
            emptyFallback: WritingCoachLayoutSupport.emptyImprovementsFallback
        )

        let stack = NSStackView(views: [strengthPanel, improvementPanel])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = WritingCoachLayoutSupport.panelSpacing

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true

        let fittingSize = stack.fittingSize
        stack.frame = NSRect(x: 0, y: 0, width: width, height: fittingSize.height)

        return stack
    }

    private func buildCoachPanel(
        title: String,
        items: [String],
        prefix: String,
        accentColor: NSColor,
        contentWidth: CGFloat,
        emptyFallback: String
    ) -> NSView {
        let inset = WritingCoachLayoutSupport.panelInset

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.cornerRadius = WritingCoachLayoutSupport.cornerRadius
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = accentColor.withAlphaComponent(WritingCoachLayoutSupport.borderAlpha).cgColor
        panel.layer?.backgroundColor = accentColor.withAlphaComponent(WritingCoachLayoutSupport.backgroundAlpha).cgColor

        let headerField = NSTextField(labelWithString: title)
        headerField.font = NSFont.systemFont(ofSize: WritingCoachLayoutSupport.headerFontSize, weight: .semibold)
        headerField.textColor = accentColor

        let displayItems = items.isEmpty ? [emptyFallback] : items
        let itemFields: [NSTextField] = displayItems.map { text in
            let attributed = NSMutableAttributedString()
            let prefixAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: accentColor,
                .font: NSFont.systemFont(ofSize: WritingCoachLayoutSupport.itemFontSize)
            ]
            let textAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: WritingCoachLayoutSupport.itemFontSize)
            ]
            attributed.append(NSAttributedString(string: prefix, attributes: prefixAttrs))
            attributed.append(NSAttributedString(string: text, attributes: textAttrs))

            let field = NSTextField(wrappingLabelWithString: "")
            field.attributedStringValue = attributed
            field.preferredMaxLayoutWidth = contentWidth
            return field
        }

        var views: [NSView] = [headerField]
        views.append(contentsOf: itemFields)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -inset),
        ])

        return panel
    }

    private func showWritingCoachFallback(rawResponse: String, sampleCount: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Sharpen My Writing Style"
        alert.informativeText = """
        Reviewed \(sampleCount) writing sample(s).

        \(rawResponse)
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func handleWritingCoachError(_ error: Error) {
        if case let ShellRunnerError.cliNotFound(provider) = error {
            setStatus("\(provider.executableName) CLI not found; update config.json")
            notifyFailure(body: "Writing Coach Failed. \(provider.displayName) CLI not found.")
            showCLIPathAlert(provider: provider)
            return
        }

        if case let ShellRunnerError.authenticationRequired(provider) = error {
            setStatus("\(provider.executableName) authentication required")
            notifyFailure(body: "Writing Coach Failed. \(provider.displayName) authentication expired. Run `\(provider.authCommand)` in Terminal.")
            showCLIAuthAlert(provider: provider)
            return
        }

        let shouldSuggestModelSwitch: Bool
        if let shellError = error as? ShellRunnerError {
            switch shellError {
            case .processFailed, .timedOut, .emptyResponse:
                shouldSuggestModelSwitch = true
            default:
                shouldSuggestModelSwitch = false
            }
        } else {
            shouldSuggestModelSwitch = false
        }

        let message: String
        if shouldSuggestModelSwitch {
            message = "\(error.localizedDescription)\nTry switching model in Settings if the selected model is busy or unavailable."
        } else {
            message = error.localizedDescription
        }
        setStatus("Writing coach failed")
        notifyFailure(body: "Writing Coach Failed. \(message)")
        showFailureAlert(title: "Writing Coach Failed", message: message)
    }

    private func showFailureAlert(title: String, message: String) {
        let present: () -> Void = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }

    private func refreshHistoryWindowIfVisible() {
        let entries = historyStore.load().reversed()
        let snapshot = Array(entries)
        DispatchQueue.main.async { [weak self] in
            self?.historyWindowController?.update(entries: snapshot)
        }
    }

    private func restoreClipboardSnapshot(after delay: TimeInterval) {
        guard let snapshot = clipboardSnapshot else {
            return
        }

        clipboardSnapshot = nil

        let restore: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.clipboardManager.restore(snapshot)
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restore)
        } else {
            restore()
        }
    }

    private func syncLaunchAtLoginPreferenceSilently() {
        let config = configManager.loadConfig()
        let launchAtLogin = config.launchAtLogin
        try? historyStore.trim(limit: config.historyLimit)
        try? LaunchAtLoginManager.setEnabled(launchAtLogin)
    }

    private func recordHistoryEntry(
        originalText: String,
        generatedText: String,
        provider: CLIProvider,
        model: String,
        startedAt: Date,
        succeeded: Bool
    ) {
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = normalizedModel.isEmpty ? AppConfig.defaultModel(for: provider) : normalizedModel
        let historyLimit = configManager.loadConfig().historyLimit

        let entry = CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            originalText: originalText,
            generatedText: generatedText,
            provider: provider.displayName,
            model: modelName,
            durationMilliseconds: max(0, elapsed),
            succeeded: succeeded
        )

        try? historyStore.append(entry, limit: historyLimit)
        refreshHistoryWindowIfVisible()
    }

    private func showFatalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

final class SettingsWindowController: NSWindowController {
    struct ModelOption {
        let title: String
        let value: String?
    }

    private let configManager: ConfigManager
    private let onConfigSaved: (AppConfig) -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customModelField = NSTextField(string: "")
    private let customModelContainer = NSStackView()
    private let hotkeyKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let commandModifierCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let optionModifierCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let controlModifierCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let shiftModifierCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let hotkeyPreviewLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Start GhostEdit automatically when you log in",
        target: nil,
        action: nil
    )
    private let historyLimitField = NSTextField(string: "")
    private let timeoutField = NSTextField(string: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let rootStack = NSStackView()

    private let providerOptions: [CLIProvider] = [.claude, .codex, .gemini]
    private let hotkeyKeyOptions = HotkeySupport.keyOptions
    private var modelOptions: [ModelOption] = []

    init(configManager: ConfigManager, onConfigSaved: @escaping (AppConfig) -> Void) {
        self.configManager = configManager
        self.onConfigSaved = onConfigSaved

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsLayoutSupport.windowWidth,
                height: SettingsLayoutSupport.minWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostEdit Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(
            width: SettingsLayoutSupport.windowWidth,
            height: SettingsLayoutSupport.minWindowHeight
        )
        window.center()

        super.init(window: window)
        buildUI()
        loadCurrentValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        rootStack.orientation = .vertical
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        let subtitle = NSTextField(labelWithString: "Choose provider/model, hotkey, timeout, and how many past corrections to keep.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
        rootStack.addArrangedSubview(subtitle)

        let providerLabel = makeFieldLabel("Provider")
        let providerRow = makeRow(label: providerLabel, field: providerPopup)
        rootStack.addArrangedSubview(providerRow)

        providerPopup.removeAllItems()
        providerOptions.forEach { providerPopup.addItem(withTitle: $0.displayName) }
        providerPopup.target = self
        providerPopup.action = #selector(providerPopupChanged)

        let modelLabel = makeFieldLabel("Model")
        let modelRow = makeRow(label: modelLabel, field: modelPopup)
        rootStack.addArrangedSubview(modelRow)

        modelPopup.target = self
        modelPopup.action = #selector(modelPopupChanged)

        let customLabel = makeFieldLabel("Custom")
        customModelField.placeholderString = "Enter custom model name"
        customModelContainer.orientation = .horizontal
        customModelContainer.spacing = 12
        customModelContainer.alignment = .firstBaseline
        customModelContainer.addArrangedSubview(customLabel)
        customModelContainer.addArrangedSubview(customModelField)
        rootStack.addArrangedSubview(customModelContainer)

        let hotkeyKeyLabel = makeFieldLabel("Hotkey")
        hotkeyKeyPopup.removeAllItems()
        hotkeyKeyOptions.forEach { option in
            hotkeyKeyPopup.addItem(withTitle: option.title)
        }
        hotkeyKeyPopup.target = self
        hotkeyKeyPopup.action = #selector(hotkeyInputChanged)
        let hotkeyKeyRow = makeRow(label: hotkeyKeyLabel, field: hotkeyKeyPopup)
        rootStack.addArrangedSubview(hotkeyKeyRow)

        commandModifierCheckbox.target = self
        commandModifierCheckbox.action = #selector(hotkeyInputChanged)
        optionModifierCheckbox.target = self
        optionModifierCheckbox.action = #selector(hotkeyInputChanged)
        controlModifierCheckbox.target = self
        controlModifierCheckbox.action = #selector(hotkeyInputChanged)
        shiftModifierCheckbox.target = self
        shiftModifierCheckbox.action = #selector(hotkeyInputChanged)

        let hotkeyModifiersStack = NSStackView()
        hotkeyModifiersStack.orientation = .horizontal
        hotkeyModifiersStack.spacing = 8
        hotkeyModifiersStack.addArrangedSubview(commandModifierCheckbox)
        hotkeyModifiersStack.addArrangedSubview(optionModifierCheckbox)
        hotkeyModifiersStack.addArrangedSubview(controlModifierCheckbox)
        hotkeyModifiersStack.addArrangedSubview(shiftModifierCheckbox)

        let hotkeyModifiersLabel = makeFieldLabel("Modifiers")
        let hotkeyModifiersRow = makeRow(label: hotkeyModifiersLabel, field: hotkeyModifiersStack)
        rootStack.addArrangedSubview(hotkeyModifiersRow)

        hotkeyPreviewLabel.textColor = .secondaryLabelColor
        hotkeyPreviewLabel.maximumNumberOfLines = 2
        hotkeyPreviewLabel.lineBreakMode = .byWordWrapping
        rootStack.addArrangedSubview(hotkeyPreviewLabel)

        launchAtLoginCheckbox.setContentHuggingPriority(.required, for: .vertical)
        rootStack.addArrangedSubview(launchAtLoginCheckbox)

        let historyLimitLabel = makeFieldLabel("History N")
        historyLimitField.placeholderString = "200"
        historyLimitField.alignment = .left
        let historyLimitRow = makeRow(label: historyLimitLabel, field: historyLimitField)
        rootStack.addArrangedSubview(historyLimitRow)

        let timeoutLabel = makeFieldLabel("Timeout")
        timeoutField.placeholderString = "60"
        timeoutField.alignment = .left
        let timeoutRow = makeRow(label: timeoutLabel, field: timeoutField)
        rootStack.addArrangedSubview(timeoutRow)

        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 3
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        rootStack.addArrangedSubview(hintLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        rootStack.addArrangedSubview(spacer)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        buttonRow.addArrangedSubview(closeButton)
        buttonRow.addArrangedSubview(saveButton)
        rootStack.addArrangedSubview(buttonRow)

        updateWindowHeightToFitContent()
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        return label
    }

    private func makeRow(label: NSTextField, field: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        return row
    }

    private func loadCurrentValues() {
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let providerIndex = providerOptions.firstIndex(of: provider) ?? 0
        providerPopup.selectItem(at: providerIndex)
        launchAtLoginCheckbox.state = config.launchAtLogin ? .on : .off
        historyLimitField.stringValue = "\(config.historyLimit)"
        timeoutField.stringValue = "\(config.timeoutSeconds)"
        loadHotkeyValues(from: config)

        let rawModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = rawModel.isEmpty ? AppConfig.defaultModel(for: provider) : rawModel
        reloadModelOptions(for: provider, selectedModel: selectedModel)
        updateWindowHeightToFitContent()
    }

    @objc private func providerPopupChanged() {
        let provider = selectedProvider()
        reloadModelOptions(for: provider, selectedModel: AppConfig.defaultModel(for: provider))
    }

    @objc private func modelPopupChanged() {
        refreshCustomFieldVisibility()
    }

    @objc private func hotkeyInputChanged() {
        updateHotkeyPreview()
    }

    private func reloadModelOptions(for provider: CLIProvider, selectedModel: String) {
        modelOptions = modelOptionsForProvider(provider)
        modelPopup.removeAllItems()
        modelOptions.forEach { modelPopup.addItem(withTitle: $0.title) }

        if let index = modelOptions.firstIndex(where: { $0.value == selectedModel }) {
            modelPopup.selectItem(at: index)
            customModelField.stringValue = ""
        } else {
            modelPopup.selectItem(at: modelOptions.count - 1)
            customModelField.stringValue = selectedModel
        }

        refreshCustomFieldVisibility()
        updateHint(for: provider)
    }

    private func modelOptionsForProvider(_ provider: CLIProvider) -> [ModelOption] {
        let predefined = provider.availableModels.map { modelName in
            ModelOption(title: modelName, value: modelName)
        }
        return predefined + [ModelOption(title: "Custom", value: nil)]
    }

    private func updateHint(for provider: CLIProvider) {
        hintLabel.stringValue = "If a \(provider.displayName) model is busy or fails, switch models and retry. Default: \(provider.defaultModel)."
    }

    private func loadHotkeyValues(from config: AppConfig) {
        if let index = hotkeyKeyOptions.firstIndex(where: { $0.keyCode == config.hotkeyKeyCode }) {
            hotkeyKeyPopup.selectItem(at: index)
        } else if let defaultIndex = hotkeyKeyOptions.firstIndex(where: { $0.keyCode == HotkeySupport.defaultKeyCode }) {
            hotkeyKeyPopup.selectItem(at: defaultIndex)
        } else {
            hotkeyKeyPopup.selectItem(at: 0)
        }

        let split = HotkeySupport.splitModifiers(config.hotkeyModifiers)
        commandModifierCheckbox.state = split.command ? .on : .off
        optionModifierCheckbox.state = split.option ? .on : .off
        controlModifierCheckbox.state = split.control ? .on : .off
        shiftModifierCheckbox.state = split.shift ? .on : .off

        updateHotkeyPreview()
    }

    private func selectedHotkeyKeyCode() -> UInt32? {
        let index = hotkeyKeyPopup.indexOfSelectedItem
        guard hotkeyKeyOptions.indices.contains(index) else {
            return nil
        }
        return hotkeyKeyOptions[index].keyCode
    }

    private func selectedHotkeyModifiers() -> UInt32 {
        HotkeySupport.makeModifiers(
            command: commandModifierCheckbox.state == .on,
            option: optionModifierCheckbox.state == .on,
            control: controlModifierCheckbox.state == .on,
            shift: shiftModifierCheckbox.state == .on
        )
    }

    private func updateHotkeyPreview() {
        guard let keyCode = selectedHotkeyKeyCode() else {
            hotkeyPreviewLabel.stringValue = "Current hotkey: unavailable"
            return
        }

        let modifiers = selectedHotkeyModifiers()
        let display = HotkeySupport.displayString(keyCode: keyCode, modifiers: modifiers)
        hotkeyPreviewLabel.stringValue = "Current hotkey: \(display)"
    }

    private func refreshCustomFieldVisibility() {
        let isCustom = selectedOptionValue() == nil
        customModelContainer.isHidden = !isCustom
        if isCustom {
            customModelField.becomeFirstResponder()
        }
        updateWindowHeightToFitContent()
    }

    private func updateWindowHeightToFitContent() {
        guard let window, let contentView = window.contentView else {
            return
        }

        contentView.layoutSubtreeIfNeeded()
        let preferredHeight = SettingsLayoutSupport.preferredWindowHeight(for: rootStack.fittingSize.height)
        window.contentMinSize = NSSize(width: SettingsLayoutSupport.windowWidth, height: preferredHeight)
        window.setContentSize(NSSize(width: SettingsLayoutSupport.windowWidth, height: preferredHeight))
    }

    private func selectedOptionValue() -> String? {
        let index = modelPopup.indexOfSelectedItem
        guard modelOptions.indices.contains(index) else {
            return modelOptions.first?.value
        }

        return modelOptions[index].value
    }

    private func selectedProvider() -> CLIProvider {
        let index = providerPopup.indexOfSelectedItem
        guard providerOptions.indices.contains(index) else {
            return .default
        }
        return providerOptions[index]
    }

    private func selectedModel() -> String {
        if let fixedValue = selectedOptionValue() {
            return fixedValue
        }

        return customModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func saveClicked() {
        let provider = selectedProvider()
        let model = selectedModel()
        let historyLimitText = historyLimitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutText = timeoutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hotkeyKeyCode = selectedHotkeyKeyCode() else {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Hotkey key is required"
            alert.informativeText = "Choose a hotkey key before saving."
            alert.runModal()
            return
        }
        let hotkeyModifiers = selectedHotkeyModifiers()
        if selectedOptionValue() == nil, model.isEmpty {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Model is required"
            alert.informativeText = "Choose a model or enter a custom model name."
            alert.runModal()
            return
        }
        if hotkeyModifiers == 0 {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Hotkey modifiers are required"
            alert.informativeText = "Select at least one modifier key (Command, Option, Control, or Shift)."
            alert.runModal()
            return
        }
        guard let historyLimit = Int(historyLimitText), historyLimit > 0 else {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "History size is invalid"
            alert.informativeText = "Enter a whole number greater than 0 for History N."
            alert.runModal()
            return
        }
        guard let timeoutSeconds = Int(timeoutText), timeoutSeconds >= 5 else {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Timeout is invalid"
            alert.informativeText = "Enter a whole number of at least 5 for Timeout (seconds)."
            alert.runModal()
            return
        }

        var config = configManager.loadConfig()
        config.provider = provider.rawValue
        config.model = model
        config.hotkeyKeyCode = hotkeyKeyCode
        config.hotkeyModifiers = hotkeyModifiers
        config.launchAtLogin = (launchAtLoginCheckbox.state == .on)
        config.historyLimit = historyLimit
        config.timeoutSeconds = timeoutSeconds

        do {
            try configManager.saveConfig(config)
            do {
                try LaunchAtLoginManager.setEnabled(config.launchAtLogin)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could not update Launch at Login"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            onConfigSaved(config)
            close()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Failed to Save Settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func closeClicked() {
        close()
    }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = HistoryCopyTableView(frame: .zero)
    private let emptyLabel = NSTextField(labelWithString: "No corrections yet.")
    private let cellFont = NSFont.systemFont(ofSize: 12)
    private var rows: [HistoryTableRow] = []
    private var entries: [CorrectionHistoryEntry] = []
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
    private let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostEdit History"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildUI()
        update(entries: [])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [CorrectionHistoryEntry]) {
        self.entries = entries
        rows = HistoryTableModel.rows(
            from: entries,
            timestampFormatter: { self.timestampFormatter.string(from: $0) }
        )

        tableView.reloadData()
        refreshRowHeights()
        emptyLabel.isHidden = !rows.isEmpty
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        let subtitle = NSTextField(
            labelWithString: "Latest corrections (newest first). Click a cell and press Cmd+C to copy that cell."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping
        rootStack.addArrangedSubview(subtitle)

        let controlsRow = NSStackView()
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 10
        controlsRow.alignment = .centerY

        let exportButton = NSButton(title: "Export CSV...", target: self, action: #selector(exportCSVClicked))
        controlsRow.addArrangedSubview(exportButton)
        controlsRow.addArrangedSubview(NSView())
        rootStack.addArrangedSubview(controlsRow)

        emptyLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(emptyLabel)

        configureTableView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        rootStack.addArrangedSubview(scrollView)
    }

    private func configureTableView() {
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 8, height: 6)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.copyHandler = { [weak self] in
            self?.copySelectedCellToPasteboard() ?? false
        }

        let menu = NSMenu()
        let copyCellItem = NSMenuItem(title: "Copy Cell", action: #selector(copyCellAction), keyEquivalent: "")
        copyCellItem.target = self
        menu.addItem(copyCellItem)
        tableView.menu = menu

        HistoryTableColumn.allCases.forEach { column in
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = title(for: column)
            tableColumn.width = width(for: column)
            tableColumn.minWidth = minWidth(for: column)
            tableColumn.resizingMask = .autoresizingMask
            tableView.addTableColumn(tableColumn)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableColumnDidResize),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
    }

    private func title(for column: HistoryTableColumn) -> String {
        switch column {
        case .timestamp:
            return "Timestamp"
        case .status:
            return "Status"
        case .provider:
            return "Provider"
        case .model:
            return "Model"
        case .duration:
            return "Duration"
        case .original:
            return "Original Text"
        case .generated:
            return "Generated Text"
        }
    }

    private func width(for column: HistoryTableColumn) -> CGFloat {
        switch column {
        case .timestamp:
            return 170
        case .status:
            return 90
        case .provider:
            return 90
        case .model:
            return 170
        case .duration:
            return 100
        case .original:
            return 320
        case .generated:
            return 320
        }
    }

    private func minWidth(for column: HistoryTableColumn) -> CGFloat {
        switch column {
        case .timestamp:
            return 140
        case .status:
            return 70
        case .provider:
            return 70
        case .model:
            return 120
        case .duration:
            return 80
        case .original:
            return 220
        case .generated:
            return 220
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else {
            return 30
        }

        let padding: CGFloat = 10
        var maxTextHeight: CGFloat = 20
        let currentRow = rows[row]
        for column in HistoryTableColumn.allCases {
            guard
                let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.rawValue))
            else {
                continue
            }

            let value = currentRow.value(for: column)
            let availableWidth = max(40, tableColumn.width - 12)
            let bounds = (value as NSString).boundingRect(
                with: NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: cellFont]
            )
            maxTextHeight = max(maxTextHeight, ceil(bounds.height))
        }

        return max(30, maxTextHeight + padding)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard
            rows.indices.contains(row),
            let tableColumn,
            let column = HistoryTableColumn(rawValue: tableColumn.identifier.rawValue)
        else {
            return nil
        }

        let text = rows[row].value(for: column)
        let viewID = NSUserInterfaceItemIdentifier("HistoryCell-\(column.rawValue)")

        let cellView: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: viewID, owner: self) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView(frame: .zero)
            cellView.identifier = viewID

            let textField = NSTextField(frame: .zero)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isSelectable = true
            textField.isBordered = false
            textField.drawsBackground = false
            textField.usesSingleLineMode = false
            textField.maximumNumberOfLines = 0
            textField.lineBreakMode = .byWordWrapping
            textField.font = cellFont
            cellView.textField = textField
            cellView.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                textField.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),
                textField.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -4)
            ])
        }

        cellView.textField?.stringValue = text
        cellView.textField?.toolTip = text
        return cellView
    }

    @objc private func copyCellAction() {
        _ = copySelectedCellToPasteboard()
    }

    @objc private func exportCSVClicked() {
        let panel = NSSavePanel()
        panel.title = "Export History CSV"
        panel.message = "Choose where to save the history export."
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ghostedit-history-\(fileTimestampFormatter.string(from: Date())).csv"

        guard panel.runModal() == .OK, let chosenURL = panel.url else {
            return
        }

        let exportURL: URL
        if chosenURL.pathExtension.lowercased() == "csv" {
            exportURL = chosenURL
        } else {
            exportURL = chosenURL.appendingPathExtension("csv")
        }

        let csv = HistoryCSVExporter.csv(
            entries: entries,
            timestampFormatter: { self.timestampFormatter.string(from: $0) }
        )

        do {
            try csv.write(to: exportURL, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func tableColumnDidResize(_ notification: Notification) {
        refreshRowHeights()
    }

    private func refreshRowHeights() {
        guard !rows.isEmpty else {
            return
        }

        let indexes = IndexSet(integersIn: 0..<rows.count)
        tableView.noteHeightOfRows(withIndexesChanged: indexes)
    }

    @discardableResult
    private func copySelectedCellToPasteboard() -> Bool {
        guard
            let (rowIndex, column) = selectedCellLocation(),
            rows.indices.contains(rowIndex)
        else {
            NSSound.beep()
            return false
        }

        let value = rows[rowIndex].value(for: column)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return true
    }

    private func selectedCellLocation() -> (Int, HistoryTableColumn)? {
        let rowCandidates = [tableView.clickedRow, tableView.activeRow, tableView.selectedRow]
        guard let rowIndex = rowCandidates.first(where: { rows.indices.contains($0) }) else {
            return nil
        }

        let columnCandidates = [tableView.clickedColumn, tableView.activeColumn]
        for columnIndex in columnCandidates where tableView.tableColumns.indices.contains(columnIndex) {
            let identifier = tableView.tableColumns[columnIndex].identifier.rawValue
            if let mapped = HistoryTableColumn(rawValue: identifier) {
                return (rowIndex, mapped)
            }
        }

        return (rowIndex, .generated)
    }
}

private final class HistoryCopyTableView: NSTableView {
    var activeRow: Int = -1
    var activeColumn: Int = -1
    var copyHandler: (() -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        activeRow = row(at: location)
        activeColumn = column(at: location)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command), characters == "c", copyHandler?() == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class HUDOverlayController {
    private var panel: NSPanel?
    private var ghostImageView: NSImageView?
    private var messageLabel: NSTextField?
    private var dismissWorkItem: DispatchWorkItem?
    private var ghostWithSpectacles: NSImage?
    private var ghostWithoutSpectacles: NSImage?

    func show(state: HUDOverlayState) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if panel == nil {
            buildPanel()
        }

        applyContent(for: state)

        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = TimeInterval(HUDOverlaySupport.fadeInDuration)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        scheduleAutoDismissIfNeeded(for: state)
    }

    func update(state: HUDOverlayState) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if panel == nil {
            buildPanel()
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

    private func buildPanel() {
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

        let stack = NSStackView(views: [imageView, message])
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

        newPanel.contentView = effectView

        self.panel = newPanel
        self.ghostImageView = imageView
        self.messageLabel = message
    }

    private func applyContent(for state: HUDOverlayState) {
        let content = HUDOverlaySupport.content(for: state)
        messageLabel?.stringValue = content.message

        let spectacles = HUDOverlaySupport.showsSpectacles(for: state)
        ghostImageView?.image = renderGhostImage(
            size: HUDOverlaySupport.iconSize,
            spectacles: spectacles
        )
    }

    private func scheduleAutoDismissIfNeeded(for state: HUDOverlayState) {
        guard let delay = HUDOverlaySupport.autoDismissDelay(for: state) else {
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
