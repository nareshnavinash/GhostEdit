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
        let nsText = text as NSString
        let clampedLocation = max(0, min(cursorLocation, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: clampedLocation, length: 0))
        guard lineRange.length > 0 else { return nil }
        var lineText = nsText.substring(with: lineRange)
        // Trim trailing newline for correction but preserve range for reconstruction
        if lineText.hasSuffix("\n") {
            lineText = String(lineText.dropLast())
        }
        guard !lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (lineText, lineRange)
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
        var merged = harper
        for nsIssue in nsChecker {
            let overlaps = harper.contains { h in
                h.range.intersection(nsIssue.range) != nil
            }
            if !overlaps {
                merged.append(nsIssue)
            }
        }
        // Filter out likely proper nouns (names) and acronyms from spelling issues
        merged = SpellCheckSupport.filterProperNouns(merged, in: text)
        merged = SpellCheckSupport.filterAcronyms(merged)
        return SpellCheckSupport.truncateForDisplay(merged)
    }

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

    private func finishProcessing() {
        isProcessing = false
        pendingDiffOriginalText = nil
        pendingLineContext = nil
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

    private func setStatus(_ text: String) {
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        let modelDisplay = model.isEmpty ? provider.defaultModel : model
        statusMenuItem?.title = "\(provider.displayName) · \(modelDisplay)"
        statusDetailMenuItem?.title = text

        // Update status dot color on detail item
        let dotColor: NSColor
        if text == "Idle" || text.hasPrefix("Last correction") || text.hasPrefix("Settings saved") {
            dotColor = .systemGreen
        } else if text.contains("Processing") || text.contains("Working") || text.contains("Copying") || text.contains("Analyzing") || text.contains("Checking") || text.contains("Retrying") {
            dotColor = .systemOrange
        } else if text.contains("failed") || text.contains("not found") || text.contains("required") || text.contains("No text") || text.contains("permission") {
            dotColor = .systemRed
        } else {
            dotColor = .systemGreen
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

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = HistoryCopyTableView(frame: .zero)
    private let emptyLabel = NSTextField(labelWithString: "No corrections yet")
    private var emptyStateContainer: NSView?
    private let cellFont = NSFont.systemFont(ofSize: 12)
    private var rows: [HistoryTableRow] = []
    private var filteredRows: [HistoryTableRow] = []
    private var filteredEntries: [CorrectionHistoryEntry] = []
    private var entries: [CorrectionHistoryEntry] = []
    private let searchField = NSSearchField()
    private let filterSegment = NSSegmentedControl(labels: ["All", "Success", "Failed"], trackingMode: .selectOne, target: nil, action: nil)
    private var currentFilter: Int = 0  // 0=All, 1=Success, 2=Failed
    private var searchQuery: String = ""
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
        window.setFrameAutosaveName("GhostEditHistory")
        if !window.setFrameUsingName("GhostEditHistory") { window.center() }

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
        applyFilters()
    }

    private func applyFilters() {
        var zipped = Array(zip(entries, rows))

        // Apply status filter
        switch currentFilter {
        case 1: zipped = zipped.filter { $0.0.succeeded }
        case 2: zipped = zipped.filter { !$0.0.succeeded }
        default: break
        }

        // Apply search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            zipped = zipped.filter { entry, row in
                row.original.lowercased().contains(query)
                    || row.generated.lowercased().contains(query)
                    || row.provider.lowercased().contains(query)
                    || row.model.lowercased().contains(query)
            }
        }

        filteredEntries = zipped.map(\.0)
        filteredRows = zipped.map(\.1)

        tableView.reloadData()
        refreshRowHeights()
        emptyStateContainer?.isHidden = !filteredRows.isEmpty
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

        filterSegment.selectedSegment = 0
        filterSegment.target = self
        filterSegment.action = #selector(filterSegmentChanged)
        controlsRow.addArrangedSubview(filterSegment)

        searchField.placeholderString = "Search corrections..."
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        controlsRow.addArrangedSubview(searchField)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlsRow.addArrangedSubview(spacer)

        let exportButton = NSButton(title: "Export CSV...", target: self, action: #selector(exportCSVClicked))
        controlsRow.addArrangedSubview(exportButton)
        rootStack.addArrangedSubview(controlsRow)

        // Empty state: ghost icon + styled message
        let emptyContainer = NSView()
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.identifier = NSUserInterfaceItemIdentifier("emptyStateContainer")

        let ghostIcon = NSTextField(labelWithString: "\u{1F47B}")
        ghostIcon.font = .systemFont(ofSize: 48)
        ghostIcon.alignment = .center
        ghostIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(ghostIcon)

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(emptyLabel)

        let emptySubtext = NSTextField(labelWithString: "Corrections will appear here after you use the hotkey.")
        emptySubtext.font = .systemFont(ofSize: 12)
        emptySubtext.textColor = .quaternaryLabelColor
        emptySubtext.alignment = .center
        emptySubtext.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(emptySubtext)

        NSLayoutConstraint.activate([
            ghostIcon.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            ghostIcon.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: 40),
            emptyLabel.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: ghostIcon.bottomAnchor, constant: 12),
            emptySubtext.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptySubtext.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 6),
            emptySubtext.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor),
            emptyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])

        rootStack.addArrangedSubview(emptyContainer)
        self.emptyStateContainer = emptyContainer

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
        filteredRows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard filteredRows.indices.contains(row) else {
            return 30
        }

        let padding: CGFloat = 10
        var maxTextHeight: CGFloat = 20
        let currentRow = filteredRows[row]
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
            filteredRows.indices.contains(row),
            let tableColumn,
            let column = HistoryTableColumn(rawValue: tableColumn.identifier.rawValue)
        else {
            return nil
        }

        let text = filteredRows[row].value(for: column)

        // Status column: use a colored badge instead of plain text
        if column == .status {
            let succeeded = filteredEntries.indices.contains(row) && filteredEntries[row].succeeded
            return makeStatusBadgeView(succeeded: succeeded, in: tableView)
        }

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

        // Long text columns: limit display lines, lighter for preview
        if column == .original || column == .generated {
            cellView.textField?.maximumNumberOfLines = 3
            cellView.textField?.lineBreakMode = .byWordWrapping
            cellView.textField?.textColor = .secondaryLabelColor
        } else {
            cellView.textField?.maximumNumberOfLines = 0
            cellView.textField?.lineBreakMode = .byWordWrapping
        }

        // Duration column: color-code by speed
        if column == .duration, filteredEntries.indices.contains(row) {
            let ms = filteredEntries[row].durationMilliseconds
            let color: NSColor
            if ms < 2000 {
                color = .systemGreen
            } else if ms < 5000 {
                color = .systemOrange
            } else {
                color = .systemRed
            }
            cellView.textField?.textColor = color
            cellView.textField?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            cellView.textField?.textColor = .labelColor
            cellView.textField?.font = cellFont
        }

        // Timestamp column: show relative time
        if column == .timestamp, filteredEntries.indices.contains(row) {
            let relativeText = relativeTimestamp(for: filteredEntries[row].timestamp)
            cellView.textField?.stringValue = relativeText
            cellView.textField?.toolTip = text // Full timestamp in tooltip
        } else {
            cellView.textField?.stringValue = text
            cellView.textField?.toolTip = text
        }

        return cellView
    }

    private func relativeTimestamp(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) min\(mins == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 172800 {
            let timeStr = timeOnlyFormatter.string(from: date)
            return "Yesterday at \(timeStr)"
        } else {
            return timestampFormatter.string(from: date)
        }
    }

    private let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func makeStatusBadgeView(succeeded: Bool, in tableView: NSTableView) -> NSView {
        let viewID = NSUserInterfaceItemIdentifier("HistoryStatusBadge")
        let badgeID = NSUserInterfaceItemIdentifier("HistoryStatusBadge.badge")
        let labelID = NSUserInterfaceItemIdentifier("HistoryStatusBadge.label")
        let badgeColor: NSColor = succeeded ? .systemGreen : .systemRed
        let badgeText = succeeded ? "Succeeded" : "Failed"

        let container: NSView
        if let reused = tableView.makeView(withIdentifier: viewID, owner: self) {
            container = reused
            // Update existing badge using identifiers for reliable lookup
            if let badge = container.subviews.first(where: { $0.identifier == badgeID }) {
                badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
                badge.layer?.borderColor = badgeColor.withAlphaComponent(0.4).cgColor
                if let label = badge.subviews.first(where: { $0.identifier == labelID }) as? NSTextField {
                    label.stringValue = badgeText
                    label.textColor = badgeColor
                }
            }
        } else {
            container = NSView()
            container.identifier = viewID

            let badge = NSView()
            badge.identifier = badgeID
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
            badge.layer?.borderWidth = 0.5
            badge.layer?.borderColor = badgeColor.withAlphaComponent(0.4).cgColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(badge)

            let label = NSTextField(labelWithString: badgeText)
            label.identifier = labelID
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = badgeColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(label)

            NSLayoutConstraint.activate([
                badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
                label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -2),
                label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            ])
        }

        container.toolTip = badgeText
        return container
    }

    @objc private func copyCellAction() {
        _ = copySelectedCellToPasteboard()
    }

    @objc private func filterSegmentChanged() {
        currentFilter = filterSegment.selectedSegment
        applyFilters()
    }

    @objc private func searchFieldChanged() {
        searchQuery = searchField.stringValue
        applyFilters()
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
        guard !filteredRows.isEmpty else {
            return
        }

        let indexes = IndexSet(integersIn: 0..<filteredRows.count)
        tableView.noteHeightOfRows(withIndexesChanged: indexes)
    }

    @discardableResult
    private func copySelectedCellToPasteboard() -> Bool {
        guard
            let (rowIndex, column) = selectedCellLocation(),
            filteredRows.indices.contains(rowIndex)
        else {
            NSSound.beep()
            return false
        }

        let value = filteredRows[rowIndex].value(for: column)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return true
    }

    private func selectedCellLocation() -> (Int, HistoryTableColumn)? {
        let rowCandidates = [tableView.clickedRow, tableView.activeRow, tableView.selectedRow]
        guard let rowIndex = rowCandidates.first(where: { filteredRows.indices.contains($0) }) else {
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
                backgroundQueue.async {
                    _ = try? runner.correctText("Hello.", modelPath: modelPath, pythonPath: pythonPath, timeoutSeconds: 30)
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

        backgroundQueue.async { [weak self] in
            let corrected = try? runner.correctText(text, modelPath: modelPath, pythonPath: pythonPath, timeoutSeconds: 30)

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

