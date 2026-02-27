import AppKit
import ApplicationServices
import UserNotifications
import UniformTypeIdentifiers

public final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkeyManager = HotkeyManager()
    private let clipboardManager = ClipboardManager()
    private let configManager = ConfigManager()
    private lazy var historyStore = CorrectionHistoryStore(fileURL: configManager.historyURL)
    private lazy var shellRunner = ShellRunner(configManager: configManager)
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var hudController: HUDOverlayController?
    private var developerConsoleController: DeveloperConsoleController?
    private var diffPreviewController: DiffPreviewController?
    private var streamingPreviewController: StreamingPreviewController?
    private var liveFeedbackController: LiveFeedbackController?
    private lazy var localModelRunner: LocalModelRunner? = LocalModelRunner()

    private var statusMenu: NSMenu?
    private var statusMenuItem: NSMenuItem?
    private var statusDetailMenuItem: NSMenuItem?
    private var runNowMenuItem: NSMenuItem?
    private var undoMenuItem: NSMenuItem?
    private var historyMenuItem: NSMenuItem?
    private var writingCoachMenuItem: NSMenuItem?
    private var developerModeMenuItem: NSMenuItem?
    private var toneMenuItem: NSMenuItem?
    private var advancedSubmenuItem: NSMenuItem?
    private var checkUpdatesMenuItem: NSMenuItem?
    private var liveFeedbackMenuItem: NSMenuItem?

    private var pendingDiffOriginalText: String?
    private struct LineContext {
        let fullText: String
        let lineRange: NSRange
        let lineText: String
        let pid: pid_t
    }
    private var pendingLineContext: LineContext?
    private var isProcessing = false
    private var isShowingAccessibilityAlert = false
    private var didShowAccessibilityGuidance = false
    private var clipboardSnapshot: ClipboardManager.Snapshot?
    private var targetAppAtTrigger: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?

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

    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningUnitTests {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        setupEditMenu()
        configureStatusItem()

        do {
            try configManager.bootstrapIfNeeded()
            // Copy bundled inference script to scripts directory (requires app bundle)
            if let bundledScript = Bundle.main.path(forResource: "ghostedit_infer", ofType: "py") {
                let destScript = configManager.scriptsDirectoryURL.appendingPathComponent("ghostedit_infer.py")
                try? FileManager.default.removeItem(at: destScript)
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: bundledScript),
                    to: destScript
                )
            }
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
        if configManager.loadConfig().liveFeedbackEnabled {
            startLiveFeedback()
        }
        setStatus("Idle")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        stopLiveFeedback()
        shellRunner.killPersistentSession()
        localModelRunner?.shutdown()
        stopProcessingIndicator()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Menu Bar Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            setMenuBarIcon(idleMenuBarIcon)
            button.toolTip = "GhostEdit"
        }

        let menu = NSMenu()

        // ── Status line ──
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let modelDisplay = model.isEmpty ? provider.defaultModel : model

        let status = NSMenuItem(
            title: "\(provider.displayName) · \(modelDisplay)",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let detail = NSMenuItem(
            title: "Ready",
            action: nil,
            keyEquivalent: ""
        )
        detail.isEnabled = false
        if let img = sfSymbol("circle.fill", size: 8) {
            img.isTemplate = false
            let tinted = tintedImage(img, color: .systemGreen)
            detail.image = tinted
        }
        menu.addItem(detail)
        statusDetailMenuItem = detail

        menu.addItem(.separator())

        // ── CORRECTION section ──
        menu.addItem(sectionHeader("CORRECTION"))

        let runNow = NSMenuItem(
            title: "Fix Selected Text",
            action: #selector(runNowAction),
            keyEquivalent: ""
        )
        runNow.target = self
        runNow.image = sfSymbol("pencil.and.outline", size: 15)
        // Show current hotkey combo as tooltip hint
        let hotkeyDisplay = HotkeySupport.displayString(
            keyCode: config.hotkeyKeyCode,
            modifiers: config.hotkeyModifiers
        )
        runNow.toolTip = "Hotkey: \(hotkeyDisplay)"
        menu.addItem(runNow)
        runNowMenuItem = runNow

        let undo = NSMenuItem(
            title: "Undo Last Correction",
            action: #selector(undoLastCorrectionAction),
            keyEquivalent: ""
        )
        undo.target = self
        undo.image = sfSymbol("arrow.uturn.backward", size: 15)
        menu.addItem(undo)
        undoMenuItem = undo

        menu.addItem(.separator())

        // ── TOOLS section ──
        menu.addItem(sectionHeader("TOOLS"))

        let settings = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        settings.image = sfSymbol("gearshape", size: 15)
        menu.addItem(settings)

        let history = NSMenuItem(
            title: "History...",
            action: #selector(openHistoryAction),
            keyEquivalent: ""
        )
        history.target = self
        history.image = sfSymbol("clock", size: 15)
        menu.addItem(history)
        historyMenuItem = history

        let writingCoach = NSMenuItem(
            title: "Sharpen My Writing Style",
            action: #selector(openWritingCoachAction),
            keyEquivalent: ""
        )
        writingCoach.target = self
        writingCoach.image = sfSymbol("text.magnifyingglass", size: 15)
        menu.addItem(writingCoach)
        writingCoachMenuItem = writingCoach

        let liveFeedback = NSMenuItem(
            title: "Live Feedback",
            action: #selector(toggleLiveFeedbackAction),
            keyEquivalent: ""
        )
        liveFeedback.target = self
        liveFeedback.image = sfSymbol("waveform.badge.magnifyingglass", size: 15)
        let feedbackConfig = configManager.loadConfig()
        liveFeedback.state = feedbackConfig.liveFeedbackEnabled ? .on : .off
        menu.addItem(liveFeedback)
        liveFeedbackMenuItem = liveFeedback

        let toneItem = NSMenuItem(title: "Tone", action: nil, keyEquivalent: "")
        toneItem.image = sfSymbol("speaker.wave.2", size: 15)
        let toneSubmenu = NSMenu()
        let toneIcons: [String: String] = [
            "default": "circle", "casual": "cup.and.saucer", "professional": "briefcase",
            "academic": "graduationcap", "slack": "bubble.left"
        ]
        for preset in AppConfig.supportedPresets {
            let item = NSMenuItem(
                title: preset.capitalized,
                action: #selector(tonePresetSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            if let iconName = toneIcons[preset] {
                item.image = sfSymbol(iconName, size: 13)
            }
            toneSubmenu.addItem(item)
        }
        toneItem.submenu = toneSubmenu
        menu.addItem(toneItem)
        toneMenuItem = toneItem
        refreshToneMenuState()

        let statistics = NSMenuItem(
            title: "Statistics...",
            action: #selector(openStatisticsAction),
            keyEquivalent: ""
        )
        statistics.target = self
        statistics.image = sfSymbol("chart.bar", size: 15)
        menu.addItem(statistics)

        menu.addItem(.separator())

        // ── ADVANCED submenu ──
        let advancedItem = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        advancedItem.image = sfSymbol("wrench.and.screwdriver", size: 15)
        let advancedSubmenu = NSMenu()

        let openPrompt = NSMenuItem(
            title: "Open Prompt File",
            action: #selector(openPromptFileAction),
            keyEquivalent: ""
        )
        openPrompt.target = self
        openPrompt.image = sfSymbol("doc.text", size: 15)
        advancedSubmenu.addItem(openPrompt)

        let openConfig = NSMenuItem(
            title: "Open Config File",
            action: #selector(openConfigFileAction),
            keyEquivalent: ""
        )
        openConfig.target = self
        openConfig.image = sfSymbol("doc.badge.gearshape", size: 15)
        advancedSubmenu.addItem(openConfig)

        advancedSubmenu.addItem(.separator())

        let exportSettings = NSMenuItem(
            title: "Export Settings...",
            action: #selector(exportSettingsAction),
            keyEquivalent: ""
        )
        exportSettings.target = self
        exportSettings.image = sfSymbol("square.and.arrow.up", size: 15)
        advancedSubmenu.addItem(exportSettings)

        let importSettings = NSMenuItem(
            title: "Import Settings...",
            action: #selector(importSettingsAction),
            keyEquivalent: ""
        )
        importSettings.target = self
        importSettings.image = sfSymbol("square.and.arrow.down", size: 15)
        advancedSubmenu.addItem(importSettings)

        advancedSubmenu.addItem(.separator())

        let checkAccessibility = NSMenuItem(
            title: "Check Accessibility Permission",
            action: #selector(checkAccessibilityAction),
            keyEquivalent: ""
        )
        checkAccessibility.target = self
        checkAccessibility.image = sfSymbol("lock.shield", size: 15)
        advancedSubmenu.addItem(checkAccessibility)

        advancedSubmenu.addItem(.separator())

        let developerMode = NSMenuItem(
            title: "Developer Mode",
            action: #selector(toggleDeveloperModeAction),
            keyEquivalent: ""
        )
        developerMode.target = self
        developerMode.image = sfSymbol("terminal", size: 15)
        advancedSubmenu.addItem(developerMode)
        developerModeMenuItem = developerMode
        refreshDeveloperModeMenuState()

        advancedItem.submenu = advancedSubmenu
        menu.addItem(advancedItem)
        advancedSubmenuItem = advancedItem

        menu.addItem(.separator())

        // ── ABOUT section ──
        let version = NSMenuItem(title: appVersionText(), action: nil, keyEquivalent: "")
        version.isEnabled = false
        version.image = sfSymbol("ghost", size: 15) ?? sfSymbol("sparkles", size: 15)
        menu.addItem(version)

        let checkUpdates = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        checkUpdates.image = sfSymbol("arrow.triangle.2.circlepath", size: 15)
        menu.addItem(checkUpdates)
        checkUpdatesMenuItem = checkUpdates

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit GhostEdit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.image = sfSymbol("power", size: 15)
        quit.target = self
        menu.addItem(quit)

        statusMenu = menu
        statusItem.menu = menu
    }

    private func sfSymbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        return item
    }

    // MARK: - Menu Actions

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

    private func startLiveFeedback() {
        guard liveFeedbackController == nil else { return }
        liveFeedbackController = LiveFeedbackController(
            configManager: configManager, localModelRunner: localModelRunner
        )
        liveFeedbackController?.start()
    }

    private func stopLiveFeedback() {
        liveFeedbackController?.stop()
        liveFeedbackController = nil
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Hotkey Registration

    private func registerHotkey() {
        let config = configManager.loadConfig()

        hotkeyManager.registerDual(
            localKeyCode: config.hotkeyKeyCode,
            localModifiers: config.hotkeyModifiers,
            cloudKeyCode: config.cloudHotkeyKeyCode,
            cloudModifiers: config.cloudHotkeyModifiers
        ) { [weak self] variant in
            DispatchQueue.main.async {
                if variant == 0 {
                    // Local hotkey (e.g. Cmd+E) → local fix-all
                    self?.handleLocalFixHotkey()
                } else {
                    // Cloud hotkey (e.g. Cmd+Shift+E) → LLM correction
                    self?.handleHotkeyTrigger()
                }
            }
        }
    }

    @objc private func runNowAction() {
        statusMenu?.cancelTracking()
        handleHotkeyTrigger()
    }

    @objc private func undoLastCorrectionAction() {
        statusMenu?.cancelTracking()

        guard !isProcessing else {
            playErrorSound()
            setStatus("Already processing")
            return
        }

        guard ensureAccessibilityPermission(promptSystemDialog: false, showGuidanceAlert: true) else {
            playErrorSound()
            setStatus("Accessibility permission required")
            return
        }

        guard let entry = historyStore.lastSuccessfulEntry() else {
            playErrorSound()
            setStatus("No correction to undo")
            return
        }

        guard let targetApp = resolveTargetApplication() else {
            playErrorSound()
            setStatus("Could not determine target app; focus text app and retry")
            return
        }

        devLog(.textCapture, "Undo: restoring original text (\(entry.originalText.count) chars)")

        isProcessing = true
        targetAppAtTrigger = targetApp
        showHUD(state: .working)

        // Local fixes replace the entire field content — use AXValueAttribute directly
        if entry.provider == "Local" {
            let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
            var focusedValue: AnyObject?
            if AXUIElementCopyAttributeValue(
                appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
            ) == .success, let focused = focusedValue {
                let element = focused as! AXUIElement
                let result = AXUIElementSetAttributeValue(
                    element, kAXValueAttribute as CFString, entry.originalText as CFTypeRef
                )
                if result == .success {
                    devLog(.pasteBack, "Undo: local fix AX value replacement succeeded")
                    let time = timeFormatter.string(from: Date())
                    setStatus("Undo succeeded at \(time)")
                    updateHUD(state: .success)
                    finishProcessing()
                    return
                }
            }
            // Fall through to existing clipboard fallback if AX fails
        }

        // Try AX replacement first.
        if AccessibilityTextSupport.replaceSelectedText(
            appPID: targetApp.processIdentifier,
            with: entry.originalText
        ) {
            devLog(.pasteBack, "Undo: AX replacement succeeded")
            let time = timeFormatter.string(from: Date())
            setStatus("Undo succeeded at \(time)")
            updateHUD(state: .success)
            finishProcessing()
            return
        }

        // Fall back to clipboard paste.
        devLog(.pasteBack, "Undo: falling back to clipboard paste")
        clipboardSnapshot = clipboardManager.snapshot()
        clipboardManager.writePlainText(entry.originalText)
        targetApp.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let pasted = self.clipboardManager.simulatePasteShortcut(using: .annotatedSession)
                || self.clipboardManager.simulatePasteShortcut(using: .hidSystem)

            if pasted {
                let time = self.timeFormatter.string(from: Date())
                self.setStatus("Undo succeeded at \(time)")
                self.updateHUD(state: .success)
            } else {
                self.playErrorSound()
                self.setStatus("Undo paste failed")
                self.dismissHUD()
            }
            self.restoreClipboardSnapshot(after: 0.20)
            self.finishProcessing()
        }
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

    @objc private func toggleLiveFeedbackAction() {
        var config = configManager.loadConfig()
        config.liveFeedbackEnabled.toggle()
        try? configManager.saveConfig(config)
        liveFeedbackMenuItem?.state = config.liveFeedbackEnabled ? .on : .off
        if config.liveFeedbackEnabled {
            startLiveFeedback()
        } else {
            stopLiveFeedback()
        }
    }

    @objc private func openConfigFileAction() {
        NSWorkspace.shared.open(configManager.configURL)
    }

    @objc private func checkAccessibilityAction() {
        statusMenu?.cancelTracking()
        didShowAccessibilityGuidance = false
        _ = ensureAccessibilityPermission(promptSystemDialog: true, showGuidanceAlert: true)
    }

    @objc private func checkForUpdatesAction() {
        statusMenu?.cancelTracking()
        performUpdateCheck()
    }

    @objc private func openStatisticsAction() {
        statusMenu?.cancelTracking()
        showStatisticsWindow()
    }

    @objc private func exportSettingsAction() {
        statusMenu?.cancelTracking()
        performExportSettings()
    }

    @objc private func importSettingsAction() {
        statusMenu?.cancelTracking()
        performImportSettings()
    }

    @objc private func tonePresetSelected(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? String else { return }
        var config = configManager.loadConfig()
        config.tonePreset = preset
        try? configManager.saveConfig(config)
        refreshToneMenuState()
    }

    private func refreshToneMenuState() {
        let config = configManager.loadConfig()
        guard let submenu = toneMenuItem?.submenu else { return }
        for item in submenu.items {
            if let preset = item.representedObject as? String {
                item.state = (preset == config.tonePreset) ? .on : .off
            }
        }
    }

    @objc private func toggleDeveloperModeAction() {
        statusMenu?.cancelTracking()
        var config = configManager.loadConfig()
        config.developerMode = !config.developerMode
        try? configManager.saveConfig(config)
        refreshDeveloperModeMenuState()

        if config.developerMode {
            shellRunner.developerModeLogger = self
            showDeveloperConsole()
            devLog(.textCapture, "Developer mode enabled")
        } else {
            devLog(.textCapture, "Developer mode disabled")
            shellRunner.developerModeLogger = nil
        }
    }

    private func refreshDeveloperModeMenuState() {
        let config = configManager.loadConfig()
        developerModeMenuItem?.state = config.developerMode ? .on : .off

        if config.developerMode {
            shellRunner.developerModeLogger = self
        }
    }

    private func showDeveloperConsole() {
        if developerConsoleController == nil {
            developerConsoleController = DeveloperConsoleController()
        }
        developerConsoleController?.showWindow(nil)
        developerConsoleController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func isDeveloperModeEnabled() -> Bool {
        configManager.loadConfig().developerMode
    }

    private func devLog(_ phase: DeveloperModeLogEntry.Phase, _ message: String) {
        guard isDeveloperModeEnabled() else { return }
        let entry = DeveloperModeLogEntry(phase: phase, message: message)
        developerConsoleController?.appendEntry(entry)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Local Fix Pipeline (cmd+E)

    private func handleLocalFixHotkey() {
        guard ensureAccessibilityPermission(promptSystemDialog: false, showGuidanceAlert: true) else {
            playErrorSound()
            return
        }

        // If live feedback is active and no local model is configured, apply spell-checker fixes
        if let controller = liveFeedbackController,
           configManager.loadConfig().localModelRepoID.isEmpty {
            if let result = controller.applyAllFixes() {
                recordLocalFixHistoryEntry(original: result.original, fixed: result.fixed)
                // Get the focused AX element for popup positioning
                showHUDWithDiff(original: result.original, fixed: result.fixed, toolsUsed: "Harper + Dictionary")
            }
            return
        }
        // When a local model is configured, fall through to model-based correction below

        // Fallback: trigger a one-shot local fix on the focused text field
        guard let targetApp = NSWorkspace.shared.frontmostApplication else {
            playErrorSound()
            return
        }

        let pid = targetApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        )
        guard focusResult == .success, let focused = focusedValue else {
            playErrorSound()
            return
        }
        let element = focused as! AXUIElement
        var textValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        guard let currentText = textValue as? String, !currentText.isEmpty else {
            playErrorSound()
            return
        }

        // Save cursor position before applying fixes
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

        // Fix only the line at the cursor (not the entire document).
        // Skip for text containing U+FFFC (Slack inline emojis) — bulk text write
        // destroys object replacement characters in Electron apps.
        let lineExtraction: (lineText: String, lineRange: NSRange)?
        if currentText.contains(TokenPreservationSupport.objectReplacementCharacter) {
            lineExtraction = nil
        } else {
            lineExtraction = extractLineAtCursor(text: currentText, cursorLocation: cursorLocation)
        }
        let textToFix = lineExtraction?.lineText ?? currentText

        // Try local Hugging Face model if configured, otherwise use Harper+NSSpellChecker
        if !configManager.loadConfig().localModelRepoID.isEmpty,
           let runner = localModelRunner {
            let config = configManager.loadConfig()
            let modelPath = LocalModelSupport.modelDirectoryURL(
                baseDirectoryURL: configManager.baseDirectoryURL,
                repoID: config.localModelRepoID
            ).path
            let pythonPath = config.localModelPythonPath.isEmpty
                ? PythonEnvironmentSupport.detectPythonPath(homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)
                : config.localModelPythonPath

            // Step 1: Apply Harper + Dictionary fixes first (instant spelling/punctuation)
            let spellFixed = applyRuleBasedTextFixes(textToFix)

            showHUD(state: .working)
            let repoID = config.localModelRepoID
            Task.detached { [weak self] in
                do {
                    let protection = TokenPreservationSupport.protectTokens(in: spellFixed)
                    let textForModel = protection.hasProtectedTokens ? protection.protectedText : spellFixed
                    let prefixed = LocalModelSupport.taskPrefix(for: repoID) + textForModel
                    let rawCorrected = try runner.correctText(prefixed, modelPath: modelPath, pythonPath: pythonPath, timeoutSeconds: 120)
                    let corrected: String
                    if protection.hasProtectedTokens {
                        corrected = TokenPreservationSupport.bestEffortRestore(in: rawCorrected, tokens: protection.tokens)
                    } else {
                        corrected = rawCorrected
                    }
                    let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

                    await MainActor.run {
                        guard let self else { return }

                        // Step 2: Determine final text based on what changed
                        let finalText: String
                        let toolLabel: String
                        if trimmed.isEmpty || trimmed == spellFixed {
                            // Model returned unchanged — use spell-fixed text if it differs
                            if spellFixed == textToFix {
                                // Neither Harper nor Model changed anything
                                self.showHUD(state: .success)
                                targetApp.activate(options: [])
                                return
                            }
                            finalText = spellFixed
                            toolLabel = "Harper + Dictionary"
                        } else {
                            finalText = trimmed
                            toolLabel = spellFixed != textToFix
                                ? "Harper + Local Model" : "Local Model"
                        }

                        // Write back the corrected line (or full text if no line extraction)
                        if let extraction = lineExtraction {
                            _ = self.writeBackCorrectedLine(
                                correctedLine: finalText, lineRange: extraction.lineRange,
                                fullText: currentText, pid: pid
                            )
                        } else {
                            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, finalText as CFTypeRef)
                            self.restoreCursorPosition(
                                pid: pid, cursorLocation: cursorLocation,
                                newTextLength: (finalText as NSString).length, cursorDelta: 0
                            )
                        }
                        self.recordLocalFixHistoryEntry(original: textToFix, fixed: finalText)
                        self.showHUDWithDiff(original: textToFix, fixed: finalText, toolsUsed: toolLabel)
                        targetApp.activate(options: [])
                    }
                } catch {
                    await MainActor.run {
                        guard let self else { return }
                        self.devLog(.cliExecution, "Local model error: \(error.localizedDescription) — falling back to Harper + Dictionary")
                        // On model error, use spell-fixed text if it differs from original
                        if spellFixed != textToFix {
                            if let extraction = lineExtraction {
                                _ = self.writeBackCorrectedLine(
                                    correctedLine: spellFixed, lineRange: extraction.lineRange,
                                    fullText: currentText, pid: pid
                                )
                            } else {
                                AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, spellFixed as CFTypeRef)
                                self.restoreCursorPosition(
                                    pid: pid, cursorLocation: cursorLocation,
                                    newTextLength: (spellFixed as NSString).length, cursorDelta: 0
                                )
                            }
                            self.recordLocalFixHistoryEntry(original: textToFix, fixed: spellFixed)
                            self.showHUDWithDiff(original: textToFix, fixed: spellFixed, toolsUsed: "Harper + Dictionary")
                        }
                        targetApp.activate(options: [])
                    }
                }
            }
        } else {
            if let fixedText = applyRuleBasedFixes(
                text: textToFix, pid: pid, element: element, cursorLocation: cursorLocation,
                lineRange: lineExtraction?.lineRange, fullText: lineExtraction != nil ? currentText : nil
            ) {
                recordLocalFixHistoryEntry(original: textToFix, fixed: fixedText)
                showHUDWithDiff(original: textToFix, fixed: fixedText, toolsUsed: "Harper + Dictionary")
            }
            targetApp.activate(options: [])
        }
    }

    /// Extract the line containing the cursor position.
    /// Returns the line text (trimmed of trailing newline for correction) and its range in the full text.
    private func extractLineAtCursor(text: String, cursorLocation: Int) -> (lineText: String, lineRange: NSRange)? {
        LocalFixSupport.extractLineAtCursor(text: text, cursorLocation: cursorLocation)
    }

    /// Write back a corrected line into the full text field, placing cursor at end of fixed line.
    /// Returns true if the write succeeded via AX.
    private func writeBackCorrectedLine(
        correctedLine: String, lineRange: NSRange, fullText: String, pid: pid_t
    ) -> Bool {
        let nsFullText = fullText as NSString
        let originalLine = nsFullText.substring(with: lineRange)
        let reconstructed: String
        if originalLine.hasSuffix("\n") {
            reconstructed = nsFullText.replacingCharacters(in: lineRange, with: correctedLine + "\n")
        } else {
            reconstructed = nsFullText.replacingCharacters(in: lineRange, with: correctedLine)
        }

        // Try writing via kAXValueAttribute on a fresh focused element
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let wrote: Bool
        if AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focused = focusedValue {
            let el = focused as! AXUIElement
            wrote = AXUIElementSetAttributeValue(
                el, kAXValueAttribute as CFString, reconstructed as CFTypeRef
            ) == .success
        } else {
            wrote = false
        }

        if !wrote {
            // Fallback: replaceTextAtRange
            let cfRange = CFRange(location: lineRange.location, length: lineRange.length)
            let fallback = AccessibilityTextSupport.replaceTextAtRange(
                appPID: pid, range: cfRange, with: correctedLine
            )
            guard fallback else { return false }
        }

        // Place cursor at end of fixed line
        let cursorPos = lineRange.location + (correctedLine as NSString).length
        _ = AccessibilityTextSupport.setCursorPosition(appPID: pid, position: cursorPos)
        return true
    }

    /// Position cursor at the end of text in the focused element (for Electron apps after paste).
    private func positionCursorAtEnd(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focused = focusedValue else { return }
        let element = focused as! AXUIElement
        var textValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &textValue
        ) == .success, let text = textValue as? String else { return }
        let textLength = (text as NSString).length
        var endRange = CFRange(location: textLength, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &endRange) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeValue
            )
        }
    }

    /// Re-query the focused element and restore cursor position.
    /// Some apps invalidate the AXUIElement after text changes, so we must re-query.
    private func restoreCursorPosition(pid: pid_t, cursorLocation: Int, newTextLength: Int, cursorDelta: Int) {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focused = focusedValue else { return }
        let freshElement = focused as! AXUIElement

        let newCursorPos = max(0, min(cursorLocation + cursorDelta, newTextLength))
        var restoredRange = CFRange(location: newCursorPos, length: 0)
        if let cursorValue = AXValueCreate(.cfRange, &restoredRange) {
            AXUIElementSetAttributeValue(
                freshElement, kAXSelectedTextRangeAttribute as CFString, cursorValue
            )
        }
    }

    /// Pure-text spell polish using Harper + NSSpellChecker (no AX writes).
    /// Returns the corrected text, or the original if no fixes were found.
    private func applyRuleBasedTextFixes(_ text: String) -> String {
        let harperIssues = HarperLinter.lint(text)
        let nsIssues = performLocalSpellCheck(text)
        let allIssues = mergeIssues(harper: harperIssues, nsChecker: nsIssues, text: text)
        // Filter out issues overlapping protected tokens (@mentions, :emoji:, URLs, etc.)
        let tokenRanges = TokenPreservationSupport.tokenRanges(in: text)
        let safeIssues = tokenRanges.isEmpty ? allIssues : allIssues.filter { issue in
            !tokenRanges.contains { $0.intersection(issue.range) != nil }
        }
        let fixable = safeIssues.filter { !$0.suggestions.isEmpty }
            .sorted { $0.range.location > $1.range.location }
        guard !fixable.isEmpty else { return text }
        var nsText = text as NSString
        for issue in fixable {
            let range = issue.range
            guard range.location + range.length <= nsText.length else { continue }
            let wordAtRange = nsText.substring(with: range)
            guard wordAtRange == issue.word, let replacement = issue.suggestions.first else { continue }
            nsText = nsText.replacingCharacters(in: range, with: replacement) as NSString
        }
        return nsText as String
    }

    /// Apply fixes using Harper + NSSpellChecker (rule-based fallback).
    /// When `lineRange` and `fullText` are provided (Notes app), fixes are applied to the line text
    /// and the full document is reconstructed before writing back via AX.
    @discardableResult
    private func applyRuleBasedFixes(
        text: String, pid: pid_t, element: AXUIElement, cursorLocation: Int,
        lineRange: NSRange? = nil, fullText: String? = nil
    ) -> String? {
        let harperIssues = HarperLinter.lint(text)
        let nsIssues = performLocalSpellCheck(text)

        let allIssues = mergeIssues(harper: harperIssues, nsChecker: nsIssues, text: text)
        // Filter out issues overlapping protected tokens (@mentions, :emoji:, URLs, etc.)
        let tokenRanges = TokenPreservationSupport.tokenRanges(in: text)
        let safeIssues = tokenRanges.isEmpty ? allIssues : allIssues.filter { issue in
            !tokenRanges.contains { $0.intersection(issue.range) != nil }
        }
        let fixable = safeIssues.filter { !$0.suggestions.isEmpty }
            .sorted { $0.range.location > $1.range.location }

        guard !fixable.isEmpty else {
            showHUD(state: .success)
            return nil
        }

        var nsText = text as NSString
        var fixCount = 0
        var cursorDelta = 0
        for issue in fixable {
            let range = issue.range
            guard range.location + range.length <= nsText.length else { continue }
            let wordAtRange = nsText.substring(with: range)
            guard wordAtRange == issue.word, let replacement = issue.suggestions.first else { continue }
            nsText = nsText.replacingCharacters(in: range, with: replacement) as NSString
            fixCount += 1
            if range.location < cursorLocation {
                cursorDelta += (replacement as NSString).length - range.length
            }
        }

        if fixCount > 0 {
            if let lineRange = lineRange, let fullText = fullText {
                // Reconstruct full document with fixed line and place cursor at end of fixed line
                let fixedLine = nsText as String
                _ = writeBackCorrectedLine(
                    correctedLine: fixedLine, lineRange: lineRange,
                    fullText: fullText, pid: pid
                )
            } else {
                // Try per-word replacement first (preserves cursor in apps like Slack)
                let perWordSuccess = applyPerWordFixes(
                    fixable: fixable, text: text, pid: pid, element: element
                )
                if !perWordSuccess {
                    // Fall back to full-text replacement
                    AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nsText as CFTypeRef)
                    restoreCursorPosition(
                        pid: pid, cursorLocation: cursorLocation,
                        newTextLength: nsText.length, cursorDelta: cursorDelta
                    )
                }
            }
            showHUD(state: .successWithCount(fixCount))
            return nsText as String
        } else {
            showHUD(state: .success)
            return nil
        }
    }

    /// Apply fixes one word at a time using AX selected text range to preserve cursor position.
    private func applyPerWordFixes(
        fixable: [SpellCheckIssue],
        text: String,
        pid: pid_t,
        element: AXUIElement
    ) -> Bool {
        // Apply in reverse order so earlier ranges stay valid
        let sorted = fixable.sorted { $0.range.location > $1.range.location }
        for issue in sorted {
            guard let replacement = issue.suggestions.first else { continue }
            let range = issue.range

            // Select the word range
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
            let selectResult = AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeValue
            )
            guard selectResult == .success else { return false }

            // Replace selected text
            let replaceResult = AXUIElementSetAttributeValue(
                element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef
            )
            guard replaceResult == .success else { return false }
        }
        return true
    }

    /// Perform a local NSSpellChecker check (reused from LiveFeedbackController).
    private func performLocalSpellCheck(_ text: String) -> [SpellCheckIssue] {
        guard SpellCheckSupport.shouldCheck(text: text) else { return [] }
        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        var issues: [SpellCheckIssue] = []
        let checkingTypes: NSTextCheckingTypes =
            NSTextCheckingResult.CheckingType.spelling.rawValue |
            NSTextCheckingResult.CheckingType.grammar.rawValue |
            NSTextCheckingResult.CheckingType.correction.rawValue |
            NSTextCheckingResult.CheckingType.quote.rawValue |
            NSTextCheckingResult.CheckingType.dash.rawValue |
            NSTextCheckingResult.CheckingType.replacement.rawValue
        let results = checker.check(text, range: NSRange(location: 0, length: nsText.length),
                                    types: checkingTypes, options: nil,
                                    inSpellDocumentWithTag: 0, orthography: nil, wordCount: nil)
        for result in results {
            switch result.resultType {
            case .spelling:
                let word = nsText.substring(with: result.range)
                let guesses = checker.guesses(forWordRange: result.range, in: text,
                                              language: nil, inSpellDocumentWithTag: 0) ?? []
                issues.append(SpellCheckIssue(word: word, range: result.range, kind: .spelling, suggestions: guesses))
            case .grammar:
                for detail in (result.grammarDetails ?? []) {
                    let detailRange: NSRange
                    if let rangeValue = detail["NSGrammarRange"] as? NSValue {
                        detailRange = rangeValue.rangeValue
                    } else {
                        detailRange = result.range
                    }
                    guard detailRange.location + detailRange.length <= nsText.length else { continue }
                    let word = nsText.substring(with: detailRange)
                    let corrections = detail["NSGrammarCorrections"] as? [String] ?? []
                    issues.append(SpellCheckIssue(word: word, range: detailRange, kind: .grammar, suggestions: corrections))
                }
            case .correction:
                if let replacement = result.replacementString {
                    let word = nsText.substring(with: result.range)
                    issues.append(SpellCheckIssue(word: word, range: result.range, kind: .spelling, suggestions: [replacement]))
                }
            case .quote, .dash, .replacement:
                if let replacement = result.replacementString {
                    let word = nsText.substring(with: result.range)
                    issues.append(SpellCheckIssue(word: word, range: result.range, kind: .style, suggestions: [replacement]))
                }
            default: break
            }
        }
        return issues
    }

    /// Merge Harper and NSSpellChecker issues, preferring Harper when ranges overlap.
    private func mergeIssues(harper: [SpellCheckIssue], nsChecker: [SpellCheckIssue], text: String) -> [SpellCheckIssue] {
        LocalFixSupport.mergeIssues(harper: harper, nsChecker: nsChecker, text: text)
    }

    // MARK: - Cloud Fix Pipeline (cmd+shift+E)

    private func handleHotkeyTrigger() {
        guard ensureAccessibilityPermission(promptSystemDialog: false, showGuidanceAlert: true) else {
            playErrorSound()
            setStatus("Accessibility permission required")
            return
        }

        guard !isProcessing else {
            playErrorSound()
            setStatus("Already processing")
            return
        }

        guard let targetApp = resolveTargetApplication() else {
            playErrorSound()
            setStatus("Could not determine target app; focus text app and retry")
            return
        }

        isProcessing = true
        startProcessingIndicator()
        showHUD(state: .working)

        targetAppAtTrigger = targetApp
        devLog(.textCapture, "Target app: \(targetApp.localizedName ?? targetApp.bundleIdentifier ?? "unknown") (PID \(targetApp.processIdentifier))")

        // Try accessibility-based reading first (no clipboard round-trip needed).
        // Skip if text contains U+FFFC (Object Replacement Character) — this means
        // the source app rendered inline images (e.g. Slack custom emojis) that the
        // AX API cannot represent as text. Fall through to clipboard which has HTML.
        if let selectedText = AccessibilityTextSupport.readSelectedText(
            appPID: targetApp.processIdentifier
        ), !selectedText.contains(TokenPreservationSupport.objectReplacementCharacter) {
            devLog(.textCapture, "Read via Accessibility (\(selectedText.count) chars): \(DeveloperModeSupport.truncate(selectedText))")
            pendingLineContext = nil
            processSelectedText(selectedText)
            return
        }

        // Nothing selected — try extracting the current line at the cursor
        let pid = targetApp.processIdentifier
        if let fullText = AccessibilityTextSupport.readFullText(appPID: pid),
           !fullText.contains(TokenPreservationSupport.objectReplacementCharacter),
           let cursorPos = AccessibilityTextSupport.readCursorPosition(appPID: pid),
           let lineInfo = extractLineAtCursor(text: fullText, cursorLocation: cursorPos) {
            devLog(.textCapture, "No selection — extracted line at cursor (\(lineInfo.lineText.count) chars)")
            pendingLineContext = LineContext(
                fullText: fullText, lineRange: lineInfo.lineRange,
                lineText: lineInfo.lineText, pid: pid
            )
            processSelectedText(lineInfo.lineText)
            return
        }
        pendingLineContext = nil

        devLog(.textCapture, "Accessibility read failed or contained U+FFFC, falling back to clipboard")

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
            playErrorSound()
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
                    // Recover Slack emoji codes from HTML clipboard if the plain text
                    // contains U+FFFC (Object Replacement Characters from inline images).
                    let recovered = TokenPreservationSupport.recoverObjectReplacements(
                        in: trimmed,
                        fromHTML: clipboardManager.readHTMLString()
                    )
                    completion(recovered)
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
        pendingDiffOriginalText = selectedText
        let prompt: String
        let baseConfig = configManager.loadConfig()

        // Apply per-app profile overrides if a matching profile exists.
        let profiles = loadAppProfiles()
        let targetBundleID = targetAppAtTrigger?.bundleIdentifier
        let config = AppProfileSupport.resolvedConfig(
            base: baseConfig,
            profiles: profiles,
            bundleIdentifier: targetBundleID
        )

        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let startedAt = Date()

        if !profiles.isEmpty, let bundleID = targetBundleID {
            devLog(.textCapture, "Per-app profile check for \(bundleID): \(profiles.contains(where: { $0.bundleIdentifier == bundleID }) ? "matched" : "no match")")
        }

        // If a tone preset is active, use its prompt instead of the file prompt.
        if let presetPrompt = AppConfig.promptForPreset(config.tonePreset) {
            prompt = presetPrompt
        } else {
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
        }

        let modelDisplay = model.isEmpty ? "provider default" : model
        devLog(.cliExecution, "Processing with \(provider.executableName) (\(modelDisplay))")
        setStatus("Processing with \(provider.executableName) (\(modelDisplay))...")

        // Streaming preview path: show a floating panel that updates in real-time.
        if config.showDiffPreview {
            dismissHUD()
            stopProcessingIndicator()

            let controller = StreamingPreviewController(
                originalText: selectedText,
                onAccept: { [weak self] correctedText in
                    guard let self else { return }
                    self.streamingPreviewController = nil
                    self.applyCorrectedText(correctedText)
                },
                onCancel: { [weak self] in
                    guard let self else { return }
                    self.streamingPreviewController = nil
                    self.restoreClipboardSnapshot(after: 0)
                    self.setStatus("Correction cancelled")
                    self.finishProcessing()
                },
                onRegenerate: { }
            )
            controller.onRegenerate = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.launchStreamingRequest(
                    controller: controller,
                    prompt: prompt,
                    selectedText: selectedText,
                    provider: provider,
                    model: model
                )
            }
            streamingPreviewController = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            launchStreamingRequest(
                controller: controller,
                prompt: prompt,
                selectedText: selectedText,
                provider: provider,
                model: model
            )
            return
        }

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
                    self.updateTooltip(
                        original: selectedText,
                        corrected: correctedText,
                        provider: provider.displayName,
                        model: model
                    )

                    // Check if target app was terminated during processing.
                    if let targetApp = self.targetAppAtTrigger, targetApp.isTerminated {
                        self.clipboardManager.writePlainText(correctedText)
                        self.clipboardSnapshot = nil
                        self.dismissHUD()
                        self.setStatus("Target app closed; corrected text on clipboard")
                        self.playSuccessSound()
                        self.notifySuccessIfEnabled()
                        self.finishProcessing()
                        return
                    }

                    // Clipboard-only mode: write to clipboard without pasting back.
                    if config.clipboardOnlyMode {
                        self.clipboardManager.writePlainText(correctedText)
                        self.clipboardSnapshot = nil
                        let time = self.timeFormatter.string(from: Date())
                        self.setStatus("Corrected text copied to clipboard at \(time)")
                        self.updateHUD(state: .successWithCount(correctedText.count))
                        self.playSuccessSound()
                        self.notifySuccessIfEnabled()
                        self.finishProcessing()
                        return
                    }

                    self.devLog(.pasteBack, "Corrected text (\(correctedText.count) chars): \(DeveloperModeSupport.truncate(correctedText))")

                    // Line-at-cursor write-back for cloud hotkey
                    if let ctx = self.pendingLineContext {
                        self.devLog(.pasteBack, "Writing back corrected line via AX")
                        if self.writeBackCorrectedLine(
                            correctedLine: correctedText, lineRange: ctx.lineRange,
                            fullText: ctx.fullText, pid: ctx.pid
                        ) {
                            if let original = self.pendingDiffOriginalText {
                                self.updateHUDWithDiff(original: original, corrected: correctedText)
                            } else {
                                self.updateHUD(state: .successWithCount(correctedText.count))
                            }
                            let time = self.timeFormatter.string(from: Date())
                            self.setStatus("Last correction succeeded at \(time)")
                            self.restoreClipboardSnapshot(after: 0)
                            self.playSuccessSound()
                            self.notifySuccessIfEnabled()
                            self.finishProcessing()
                            return
                        }
                    }

                    // Try accessibility-based text replacement first (fastest path).
                    // Works on background apps — no focus changes needed.
                    if let targetApp = self.targetAppAtTrigger {
                        self.devLog(.pasteBack, "Attempting AX text replacement")
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
                                if readBack == correctedText || readBack == nil {
                                    // Verified: either text still selected and matches (TextEdit),
                                    // or app deselected after successful replacement (Notes, Mail).
                                    self.devLog(.pasteBack, "AX replacement verified successfully")
                                    if let original = self.pendingDiffOriginalText {
                                        self.updateHUDWithDiff(original: original, corrected: correctedText)
                                    } else {
                                        self.updateHUD(state: .successWithCount(correctedText.count))
                                    }
                                    let time = self.timeFormatter.string(from: Date())
                                    self.setStatus("Last correction succeeded at \(time)")
                                    self.restoreClipboardSnapshot(after: 0)
                                    self.playSuccessSound()
                                    self.notifySuccessIfEnabled()
                                    self.finishProcessing()
                                } else {
                                    // readBack is non-empty but different — AX accepted the call
                                    // but didn't actually replace (Electron: Slack, Discord, VS Code).
                                    self.devLog(.pasteBack, "AX replacement not verified, falling back to clipboard paste")
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
                // Try fallback model if the error is retriable.
                if FallbackSupport.isRetriable(error),
                   let fallbackModel = FallbackSupport.nextFallbackModel(
                       currentModel: model,
                       provider: provider
                   ) {
                    DispatchQueue.main.async {
                        self.devLog(.cliExecution, "Retrying with fallback model: \(fallbackModel)")
                        self.setStatus("Retrying with \(fallbackModel)...")
                    }
                    do {
                        var retryConfig = config
                        retryConfig.model = fallbackModel
                        let correctedText = try self.shellRunner.correctTextPreservingTokens(
                            systemPrompt: prompt,
                            selectedText: selectedText
                        )
                        self.recordHistoryEntry(
                            originalText: selectedText,
                            generatedText: correctedText,
                            provider: provider,
                            model: fallbackModel,
                            startedAt: startedAt,
                            succeeded: true
                        )
                        DispatchQueue.main.async {
                            self.updateTooltip(
                                original: selectedText,
                                corrected: correctedText,
                                provider: provider.displayName,
                                model: fallbackModel
                            )
                            self.pasteViaClipboard(correctedText: correctedText)
                        }
                        return
                    } catch {
                        // Fallback also failed — fall through to normal error handling.
                    }
                }

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

    // MARK: - Streaming

    private func launchStreamingRequest(
        controller: StreamingPreviewController,
        prompt: String,
        selectedText: String,
        provider: CLIProvider,
        model: String
    ) {
        let startedAt = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let correctedText = try self.shellRunner.correctTextStreamingPreservingTokens(
                    systemPrompt: prompt,
                    selectedText: selectedText,
                    onChunk: { accumulated in
                        controller.updateStreaming(accumulatedText: accumulated)
                    }
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
                    self.updateTooltip(
                        original: selectedText,
                        corrected: correctedText,
                        provider: provider.displayName,
                        model: model
                    )
                    controller.markComplete(correctedText: correctedText)
                }
            } catch {
                DispatchQueue.main.async {
                    controller.window?.close()
                    self.streamingPreviewController = nil
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
        undoMenuItem?.isEnabled = false
        writingCoachMenuItem?.isEnabled = false
        statusMenu?.cancelTracking()
        statusItem.menu = nil
        setMenuBarIcon(workingMenuBarIcon)
    }

    private func stopProcessingIndicator() {
        runNowMenuItem?.isEnabled = true
        undoMenuItem?.isEnabled = true
        writingCoachMenuItem?.isEnabled = true
        statusItem.menu = statusMenu
        setMenuBarIcon(idleMenuBarIcon)
    }

    // MARK: - Text Application & Write-back

    private func applyCorrectedText(_ correctedText: String) {
        devLog(.pasteBack, "Corrected text (\(correctedText.count) chars): \(DeveloperModeSupport.truncate(correctedText))")
        showHUD(state: .working)
        startProcessingIndicator()

        // Line-at-cursor write-back for cloud hotkey
        if let ctx = pendingLineContext {
            devLog(.pasteBack, "Writing back corrected line via AX")
            if writeBackCorrectedLine(
                correctedLine: correctedText, lineRange: ctx.lineRange,
                fullText: ctx.fullText, pid: ctx.pid
            ) {
                if let original = pendingDiffOriginalText {
                    updateHUDWithDiff(original: original, corrected: correctedText)
                } else {
                    updateHUD(state: .successWithCount(correctedText.count))
                }
                let time = timeFormatter.string(from: Date())
                setStatus("Last correction succeeded at \(time)")
                restoreClipboardSnapshot(after: 0)
                playSuccessSound()
                notifySuccessIfEnabled()
                finishProcessing()
                return
            }
            devLog(.pasteBack, "Line write-back failed, falling through to standard replacement")
        }

        if let targetApp = targetAppAtTrigger {
            devLog(.pasteBack, "Attempting AX text replacement")
            let axReplaced = AccessibilityTextSupport.replaceSelectedText(
                appPID: targetApp.processIdentifier,
                with: correctedText
            )
            if axReplaced {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    let readBack = AccessibilityTextSupport.readSelectedText(
                        appPID: targetApp.processIdentifier
                    )
                    if readBack == correctedText || readBack == nil {
                        self.devLog(.pasteBack, "AX replacement verified successfully")
                        if let original = self.pendingDiffOriginalText {
                            self.updateHUDWithDiff(original: original, corrected: correctedText)
                        } else {
                            self.updateHUD(state: .successWithCount(correctedText.count))
                        }
                        let time = self.timeFormatter.string(from: Date())
                        self.setStatus("Last correction succeeded at \(time)")
                        self.restoreClipboardSnapshot(after: 0)
                        self.playSuccessSound()
                        self.notifySuccessIfEnabled()
                        self.finishProcessing()
                    } else {
                        self.devLog(.pasteBack, "AX replacement not verified, falling back to clipboard paste")
                        self.pasteViaClipboard(correctedText: correctedText)
                    }
                }
                return
            }
        }

        pasteViaClipboard(correctedText: correctedText)
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
                self.playErrorSound()
                let message = "Could not paste corrected text.\n\nMake sure your cursor is in the target field, then run GhostEdit again."
                self.notifyFailure(body: "Correction Failed. \(message)")
                self.showFailureAlert(title: "Correction Failed", message: message)
                self.setStatus("Paste failed")
                self.dismissHUD()
            } else {
                if let original = self.pendingDiffOriginalText {
                    self.updateHUDWithDiff(original: original, corrected: correctedText)
                } else {
                    self.updateHUD(state: .successWithCount(correctedText.count))
                }
                let time = self.timeFormatter.string(from: Date())
                self.setStatus("Last correction succeeded at \(time)")
                self.playSuccessSound()
                self.notifySuccessIfEnabled()

                // Position cursor at end of pasted text (helps Electron apps like Slack, Discord, VS Code)
                if let targetApp = self.targetAppAtTrigger {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                        self.positionCursorAtEnd(pid: targetApp.processIdentifier)
                    }
                }

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

    // MARK: - HUD Management

    private func showHUD(state: HUDOverlayState) {
        if hudController == nil {
            hudController = HUDOverlayController()
        }
        hudController?.show(state: state)
    }

    private func updateHUD(state: HUDOverlayState) {
        hudController?.update(state: state)
    }

    private func showHUDWithDiff(original: String, fixed: String, toolsUsed: String = "") {
        let segments = DiffSupport.charDiff(old: original, new: fixed)
        guard segments.contains(where: { $0.kind != .equal }) else {
            showHUD(state: .success)
            return
        }
        let duration = TimeInterval(configManager.loadConfig().diffPreviewDuration)
        if hudController == nil { hudController = HUDOverlayController() }
        hudController?.show(state: .successWithDiff(segments, toolsUsed: toolsUsed), dismissAfter: duration)
    }

    private func updateHUDWithDiff(original: String, corrected: String) {
        let segments = DiffSupport.charDiff(old: original, new: corrected)
        guard segments.contains(where: { $0.kind != .equal }) else {
            updateHUD(state: .successWithCount(corrected.count))
            return
        }
        let duration = TimeInterval(configManager.loadConfig().diffPreviewDuration)
        hudController?.update(state: .successWithDiff(segments, toolsUsed: ""), dismissAfter: duration)
    }

    private func dismissHUD() {
        hudController?.dismiss()
    }

    // MARK: - Processing State

    private func finishProcessing() {
        isProcessing = false
        pendingDiffOriginalText = nil
        pendingLineContext = nil
        targetAppAtTrigger = nil
        stopProcessingIndicator()
    }

    @discardableResult
    // MARK: - Accessibility & Alerts

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

    // MARK: - Sound & Notifications

    private func playErrorSound() {
        guard configManager.loadConfig().soundFeedbackEnabled else { return }
        NSSound.beep()
    }

    private func playSuccessSound() {
        guard configManager.loadConfig().soundFeedbackEnabled else { return }
        NSSound(named: "Glass")?.play()
    }

    private func notifySuccessIfEnabled() {
        guard configManager.loadConfig().notifyOnSuccess else { return }
        let content = UNMutableNotificationContent()
        content.title = "GhostEdit"
        content.body = "Correction applied successfully."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
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

    // MARK: - Status Bar

    private func setStatus(_ text: String) {
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let modelDisplay = model.isEmpty ? provider.defaultModel : model
        statusMenuItem?.title = "\(provider.displayName) · \(modelDisplay)"
        statusDetailMenuItem?.title = text

        // Update status dot color on detail item
        let dotColor: NSColor
        switch StatusDisplaySupport.statusColor(for: text) {
        case .green:  dotColor = .systemGreen
        case .orange: dotColor = .systemOrange
        case .red:    dotColor = .systemRed
        }
        if let img = sfSymbol("circle.fill", size: 8) {
            img.isTemplate = false
            statusDetailMenuItem?.image = tintedImage(img, color: dotColor)
        }

        statusItem.button?.toolTip = "GhostEdit\n\(provider.displayName) · \(modelDisplay)\n\(text)"
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
        return "Version \(shortVersion)"
    }

    // MARK: - Window Presentation

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configManager: configManager,
                localModelRunner: localModelRunner
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
                self.liveFeedbackMenuItem?.state = config.liveFeedbackEnabled ? .on : .off
                if config.liveFeedbackEnabled {
                    self.startLiveFeedback()
                } else {
                    self.stopLiveFeedback()
                }
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

    private func showStatisticsWindow() {
        let entries = historyStore.load()
        let stats = CorrectionStatisticsSupport.compute(from: entries)
        let tokenEstimate = TokenEstimationSupport.estimateCumulativeTokens(entries: entries)
        var summary = CorrectionStatisticsSupport.formattedSummary(stats)
        summary += "\n\nEstimated tokens used:"
        summary += "\n  Input: \(TokenEstimationSupport.formatTokenCount(tokenEstimate.inputTokens))"
        summary += "\n  Output: \(TokenEstimationSupport.formatTokenCount(tokenEstimate.outputTokens))"
        summary += "\n  Total: \(TokenEstimationSupport.formatTokenCount(tokenEstimate.totalTokens))"

        let alert = NSAlert()
        alert.messageText = "Correction Statistics"
        alert.informativeText = summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
        }
    }

    // MARK: - Settings Import/Export

    private func performExportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SettingsExportSupport.defaultFileName(appVersion: appVersionText())
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let config = configManager.loadConfig()
            let prompt = (try? configManager.loadPrompt()) ?? ""
            let data = try SettingsExportSupport.exportSettings(
                config: config,
                prompt: prompt,
                appVersion: appVersionText()
            )
            try data.write(to: url, options: .atomic)
            setStatus("Settings exported")
        } catch {
            showFailureAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func performImportSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try SettingsExportSupport.importSettings(from: data)
            try configManager.saveConfig(imported.config)
            if !imported.prompt.isEmpty {
                try imported.prompt.write(to: configManager.promptURL, atomically: true, encoding: .utf8)
            }
            configManager.invalidateCache()
            refreshToneMenuState()
            refreshDeveloperModeMenuState()
            setStatus("Settings imported")
        } catch {
            showFailureAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func updateTooltip(original: String, corrected: String, provider: String, model: String) {
        let tooltip = TooltipSupport.tooltip(
            lastOriginal: original,
            lastCorrected: corrected,
            lastTime: Date(),
            provider: provider,
            model: model
        )
        statusItem.button?.toolTip = tooltip
    }

    // MARK: - Update Check

    private func performUpdateCheck() {
        setStatus("Checking for updates...")

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let latestVersion = self.fetchLatestGitHubVersion()

            DispatchQueue.main.async {
                guard let latest = latestVersion else {
                    self.setStatus("Idle")
                    let alert = NSAlert()
                    alert.messageText = "Update Check"
                    alert.informativeText = "Could not reach GitHub to check for updates. Please check your internet connection."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    return
                }

                let info = UpdateCheckSupport.checkVersion(current: currentVersion, latest: latest)
                self.setStatus("Idle")

                let alert = NSAlert()
                alert.messageText = "Update Check"
                if info.isUpdateAvailable {
                    self.checkUpdatesMenuItem?.title = "Update Available (v\(info.latest))"
                    if let badge = self.sfSymbol("exclamationmark.circle.fill", size: 15) {
                        badge.isTemplate = false
                        self.checkUpdatesMenuItem?.image = self.tintedImage(badge, color: .systemOrange)
                    }
                    alert.informativeText = "A new version is available!\n\nCurrent: \(info.current)\nLatest: \(info.latest)"
                    alert.addButton(withTitle: "Open Downloads")
                    alert.addButton(withTitle: "Later")
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn, let url = URL(string: UpdateCheckSupport.defaultReleaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    alert.informativeText = "You're up to date!\n\nCurrent version: \(info.current)"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func fetchLatestGitHubVersion() -> String? {
        let apiURL = URL(string: "https://api.github.com/repos/nareshnavinash/GhostEdit/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String
            else { return }
            // Strip leading "v" from tag like "v4.3.0"
            result = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
        task.resume()
        semaphore.wait()
        return result
    }

    private func loadAppProfiles() -> [AppProfile] {
        AppProfileSupport.loadProfiles(from: configManager.profilesURL)
    }

    // MARK: - Writing Coach

    private func runWritingCoach() {
        guard !isProcessing else {
            playErrorSound()
            setStatus("Already processing")
            return
        }

        let originalSamples = historyOriginalSamples()
        guard !originalSamples.isEmpty else {
            playErrorSound()
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

    // MARK: - History

    private func refreshHistoryWindowIfVisible() {
        let entries = historyStore.load().reversed()
        let snapshot = Array(entries)
        DispatchQueue.main.async { [weak self] in
            self?.historyWindowController?.update(entries: snapshot)
        }
    }

    // MARK: - Clipboard

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

    // MARK: - Developer Mode

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

    private func recordLocalFixHistoryEntry(original: String, fixed: String) {
        let entry = CorrectionHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            originalText: original,
            generatedText: fixed,
            provider: "Local",
            model: "Harper",
            durationMilliseconds: 0,
            succeeded: true
        )
        let limit = configManager.loadConfig().historyLimit
        try? historyStore.append(entry, limit: limit)
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

extension AppDelegate: DeveloperModeLogger {
    func log(_ entry: DeveloperModeLogEntry) {
        let append: () -> Void = { [weak self] in
            self?.developerConsoleController?.appendEntry(entry)
        }
        if Thread.isMainThread {
            append()
        } else {
            DispatchQueue.main.async(execute: append)
        }
    }
}
