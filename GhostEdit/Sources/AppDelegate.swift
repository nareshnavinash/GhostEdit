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
    private var quickFixDiffPopup: QuickFixDiffPopupController?
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
        liveFeedbackController = LiveFeedbackController()
        liveFeedbackController?.start()
    }

    private func stopLiveFeedback() {
        liveFeedbackController?.stop()
        liveFeedbackController = nil
    }

    private func registerHotkey() {
        let config = configManager.loadConfig()

        hotkeyManager.registerWithVariant(
            keyCode: config.hotkeyKeyCode,
            modifiers: config.hotkeyModifiers
        ) { [weak self] variant in
            DispatchQueue.main.async {
                if variant == 0 {
                    // Base hotkey (e.g. Cmd+E) → local fix-all
                    self?.handleLocalFixHotkey()
                } else {
                    // Shift variant (e.g. Cmd+Shift+E) → LLM correction
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

        // If live feedback is active and has issues, apply all fixes
        if let controller = liveFeedbackController {
            if let result = controller.applyAllFixes() {
                recordLocalFixHistoryEntry(original: result.original, fixed: result.fixed)
                // Get the focused AX element for popup positioning
                if let targetApp = NSWorkspace.shared.frontmostApplication {
                    let appEl = AXUIElementCreateApplication(targetApp.processIdentifier)
                    var fv: AnyObject?
                    if AXUIElementCopyAttributeValue(
                        appEl, kAXFocusedUIElementAttribute as CFString, &fv
                    ) == .success, let focused = fv {
                        showQuickFixDiffPopup(
                            original: result.original, fixed: result.fixed,
                            near: focused as! AXUIElement
                        )
                    }
                }
            }
            return
        }

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

        // In Notes, only fix the line at the cursor (not the entire document)
        let isNotesApp = targetApp.bundleIdentifier == "com.apple.Notes"
        let lineExtraction: (lineText: String, lineRange: NSRange)?
        if isNotesApp {
            lineExtraction = extractLineAtCursor(text: currentText, cursorLocation: cursorLocation)
        } else {
            lineExtraction = nil
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
            let pythonPath = config.localModelPythonPath.isEmpty ? "/usr/bin/python3" : config.localModelPythonPath
            showHUD(state: .working)
            Task { @MainActor in
                do {
                    let prefixed = LocalModelSupport.taskPrefix() + textToFix
                    let corrected = try runner.correctText(prefixed, modelPath: modelPath, pythonPath: pythonPath, timeoutSeconds: 120)
                    let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !trimmed.isEmpty, trimmed != textToFix else {
                        // Model returned unchanged — fall back to rule-based
                        if let fixedText = self.applyRuleBasedFixes(
                            text: textToFix, pid: pid, element: element, cursorLocation: cursorLocation,
                            lineRange: lineExtraction?.lineRange, fullText: isNotesApp ? currentText : nil
                        ) {
                            self.recordLocalFixHistoryEntry(original: textToFix, fixed: fixedText)
                            self.showQuickFixDiffPopup(original: textToFix, fixed: fixedText, near: element)
                        } else {
                            self.showHUD(state: .success)
                        }
                        targetApp.activate(options: [])
                        return
                    }

                    // Reconstruct full text when fixing a single line in Notes
                    if let extraction = lineExtraction {
                        let nsFullText = currentText as NSString
                        let originalLine = nsFullText.substring(with: extraction.lineRange)
                        let reconstructed: String
                        if originalLine.hasSuffix("\n") {
                            reconstructed = nsFullText.replacingCharacters(in: extraction.lineRange, with: trimmed + "\n")
                        } else {
                            reconstructed = nsFullText.replacingCharacters(in: extraction.lineRange, with: trimmed)
                        }
                        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, reconstructed as CFTypeRef)
                        self.restoreCursorPosition(
                            pid: pid, cursorLocation: cursorLocation,
                            newTextLength: (reconstructed as NSString).length, cursorDelta: 0
                        )
                    } else {
                        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, trimmed as CFTypeRef)
                        self.restoreCursorPosition(
                            pid: pid, cursorLocation: cursorLocation,
                            newTextLength: (trimmed as NSString).length, cursorDelta: 0
                        )
                    }
                    self.recordLocalFixHistoryEntry(original: textToFix, fixed: trimmed)
                    self.showQuickFixDiffPopup(original: textToFix, fixed: trimmed, near: element)
                    self.showHUD(state: .success)
                    targetApp.activate(options: [])
                } catch {
                    self.devLog(.cliExecution, "Local model error: \(error.localizedDescription) — falling back to rule-based")
                    if let fixedText = self.applyRuleBasedFixes(
                        text: textToFix, pid: pid, element: element, cursorLocation: cursorLocation,
                        lineRange: lineExtraction?.lineRange, fullText: isNotesApp ? currentText : nil
                    ) {
                        self.recordLocalFixHistoryEntry(original: textToFix, fixed: fixedText)
                        self.showQuickFixDiffPopup(original: textToFix, fixed: fixedText, near: element)
                        self.showHUD(state: .fallback)
                    }
                    targetApp.activate(options: [])
                }
            }
        } else {
            if let fixedText = applyRuleBasedFixes(
                text: textToFix, pid: pid, element: element, cursorLocation: cursorLocation,
                lineRange: lineExtraction?.lineRange, fullText: isNotesApp ? currentText : nil
            ) {
                recordLocalFixHistoryEntry(original: textToFix, fixed: fixedText)
                showQuickFixDiffPopup(original: textToFix, fixed: fixedText, near: element)
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
        let fixable = allIssues.filter { !$0.suggestions.isEmpty }
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
                // Notes app: reconstruct full document with fixed line
                let nsFullText = fullText as NSString
                let originalLine = nsFullText.substring(with: lineRange)
                let fixedLine = nsText as String
                let reconstructed: String
                if originalLine.hasSuffix("\n") {
                    reconstructed = nsFullText.replacingCharacters(in: lineRange, with: fixedLine + "\n")
                } else {
                    reconstructed = nsFullText.replacingCharacters(in: lineRange, with: fixedLine)
                }
                AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, reconstructed as CFTypeRef)
                // Adjust cursor delta to be absolute (relative to line start in document)
                let absoluteCursorDelta = cursorDelta
                restoreCursorPosition(
                    pid: pid, cursorLocation: cursorLocation,
                    newTextLength: (reconstructed as NSString).length, cursorDelta: absoluteCursorDelta
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
            processSelectedText(selectedText)
            return
        }
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
                                        self.showDiffPopupForCorrection(original: original, corrected: correctedText, appPID: targetApp.processIdentifier)
                                    }
                                    let time = self.timeFormatter.string(from: Date())
                                    self.setStatus("Last correction succeeded at \(time)")
                                    self.restoreClipboardSnapshot(after: 0)
                                    self.updateHUD(state: .successWithCount(correctedText.count))
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
                let correctedText = try self.shellRunner.correctTextStreaming(
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
        quickFixDiffPopup?.dismiss()
        quickFixDiffPopup = nil
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
                            self.showDiffPopupForCorrection(original: original, corrected: correctedText, appPID: targetApp.processIdentifier)
                        }
                        let time = self.timeFormatter.string(from: Date())
                        self.setStatus("Last correction succeeded at \(time)")
                        self.restoreClipboardSnapshot(after: 0)
                        self.updateHUD(state: .successWithCount(correctedText.count))
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
                if let original = self.pendingDiffOriginalText,
                   let targetApp = self.targetAppAtTrigger {
                    self.showDiffPopupForCorrection(original: original, corrected: correctedText, appPID: targetApp.processIdentifier)
                }
                let time = self.timeFormatter.string(from: Date())
                self.setStatus("Last correction succeeded at \(time)")
                self.updateHUD(state: .successWithCount(correctedText.count))
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

    private func dismissHUD() {
        hudController?.dismiss()
    }

    private func finishProcessing() {
        isProcessing = false
        pendingDiffOriginalText = nil
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

    private func showDiffPopupForCorrection(original: String, corrected: String, appPID: pid_t) {
        let appElement = AXUIElementCreateApplication(appPID)
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focused = focusedValue else { return }
        showQuickFixDiffPopup(original: original, fixed: corrected, near: focused as! AXUIElement)
    }

    private func showQuickFixDiffPopup(original: String, fixed: String, near element: AXUIElement) {
        let segments = DiffSupport.charDiff(old: original, new: fixed)
        guard segments.contains(where: { $0.kind != .equal }) else { return }

        quickFixDiffPopup?.dismiss()

        let duration = TimeInterval(configManager.loadConfig().diffPreviewDuration)
        let popup = QuickFixDiffPopupController()
        popup.show(segments: segments, near: element, widgetFrame: liveFeedbackController?.widgetFrame, duration: duration)
        quickFixDiffPopup = popup
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

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    struct ModelOption {
        let title: String
        let value: String?
    }

    private enum Tab: String, CaseIterable {
        case general = "general"
        case hotkey = "hotkey"
        case behavior = "behavior"
        case localModels = "localModels"
        case advanced = "advanced"

        var label: String {
            switch self {
            case .general: return "General"
            case .hotkey: return "Hotkey"
            case .behavior: return "Behavior"
            case .localModels: return "Local Models"
            case .advanced: return "Advanced"
            }
        }

        var sfSymbolName: String {
            switch self {
            case .general: return "globe"
            case .hotkey: return "keyboard"
            case .behavior: return "slider.horizontal.3"
            case .localModels: return "cpu"
            case .advanced: return "wrench.and.screwdriver"
            }
        }

        var toolbarItemID: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue)
        }
    }

    private let configManager: ConfigManager
    private let onConfigSaved: (AppConfig) -> Void
    private let localModelRunner: LocalModelRunner?

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
    private let launchAtLoginSwitch = NSSwitch()
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let historyLimitField = NSTextField(string: "")
    private let timeoutField = NSTextField(string: "")
    private let soundFeedbackCheckbox = NSButton(
        checkboxWithTitle: "Play sound feedback on errors and corrections",
        target: nil,
        action: nil
    )
    private let notifyOnSuccessCheckbox = NSButton(
        checkboxWithTitle: "Show notification on successful correction",
        target: nil,
        action: nil
    )
    private let clipboardOnlyModeCheckbox = NSButton(
        checkboxWithTitle: "Clipboard-only mode (copy corrected text, do not paste back)",
        target: nil,
        action: nil
    )
    private let showDiffPreviewCheckbox = NSButton(
        checkboxWithTitle: "Show streaming preview before applying (Tab to accept, Esc to cancel)",
        target: nil,
        action: nil
    )
    private let liveFeedbackCheckbox = NSButton(
        checkboxWithTitle: "Enable live spell-check feedback while typing",
        target: nil,
        action: nil
    )
    private let tonePresetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let developerModeCheckbox = NSButton(
        checkboxWithTitle: "Enable Developer Mode (show behind-the-scenes log)",
        target: nil,
        action: nil
    )
    private let diffPreviewDurationField = NSTextField(string: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let hotkeyBadgeView = NSView()
    private let hotkeyBadgeLabel = NSTextField(labelWithString: "")

    private var tabViews: [Tab: NSView] = [:]
    private var currentTab: Tab = .general

    private let providerOptions: [CLIProvider] = [.claude, .codex, .gemini]
    private let hotkeyKeyOptions = HotkeySupport.keyOptions
    private var modelOptions: [ModelOption] = []

    init(configManager: ConfigManager, localModelRunner: LocalModelRunner? = nil, onConfigSaved: @escaping (AppConfig) -> Void) {
        self.configManager = configManager
        self.localModelRunner = localModelRunner
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
        window.title = "General"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("GhostEditSettings")
        if !window.setFrameUsingName("GhostEditSettings") { window.center() }

        super.init(window: window)
        setupToolbar()
        buildAllTabs()
        loadCurrentValues()

        // Fix window height to the tallest tab so switching never resizes
        let maxTabHeight = tabViews.values.map { $0.fittingSize.height }.max() ?? SettingsLayoutSupport.minWindowHeight
        let fixedHeight = max(ceil(maxTabHeight), SettingsLayoutSupport.minWindowHeight)
        var settingsFrame = window.frame
        let heightDelta = fixedHeight - settingsFrame.size.height
        settingsFrame.origin.y -= heightDelta
        settingsFrame.size.height = fixedHeight
        window.setFrame(settingsFrame, display: false)

        switchToTab(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        guard let window else { return }
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = Tab.general.toolbarItemID
        window.toolbar = toolbar
        window.toolbarStyle = .preference
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarItemID)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarItemID)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarItemID)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.target = self
        item.action = #selector(toolbarTabClicked(_:))
        if let img = NSImage(systemSymbolName: tab.sfSymbolName, accessibilityDescription: tab.label) {
            item.image = img
        }
        return item
    }

    @objc private func toolbarTabClicked(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        switchToTab(tab)
    }

    private func switchToTab(_ tab: Tab) {
        guard let window, let contentView = window.contentView else { return }
        let previousTab = currentTab
        currentTab = tab
        window.toolbar?.selectedItemIdentifier = tab.toolbarItemID
        window.title = tab.label

        guard let newView = tabViews[tab] else { return }

        newView.translatesAutoresizingMaskIntoConstraints = false
        newView.alphaValue = 0
        contentView.addSubview(newView)

        NSLayoutConstraint.activate([
            newView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            newView.topAnchor.constraint(equalTo: contentView.topAnchor),
            newView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            newView.animator().alphaValue = 1
            if previousTab != tab, let oldView = self.tabViews[previousTab] {
                oldView.animator().alphaValue = 0
            }
        }, completionHandler: {
            for (t, view) in self.tabViews where t != tab {
                view.removeFromSuperview()
                view.alphaValue = 1
            }
        })
    }

    // MARK: - Build Tabs

    private func buildAllTabs() {
        tabViews[.general] = buildGeneralTab()
        tabViews[.hotkey] = buildHotkeyTab()
        tabViews[.behavior] = buildBehaviorTab()
        tabViews[.localModels] = buildLocalModelsTab()
        tabViews[.advanced] = buildAdvancedTab()
    }

    // MARK: - Local Models Tab

    private var localModelsPythonPathField = NSTextField(string: "")
    private var localModelsStatusLabel = NSTextField(labelWithString: "")
    private var localModelsStatusDot = NSTextField(labelWithString: "\u{25CF}")
    private var localModelsModelRows: NSStackView = NSStackView()

    private func buildLocalModelsTab() -> NSView {
        let config = configManager.loadConfig()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.spacing = 20
        outerStack.alignment = .leading
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Section 1: Python Environment
        let pythonSection = buildLocalModelsPythonSection(config: config)
        outerStack.addArrangedSubview(pythonSection)

        // Section 2: Available Models
        let modelsSection = buildLocalModelsModelSection(config: config)
        outerStack.addArrangedSubview(modelsSection)

        // Section 3: Hardware
        let hardwareSection = buildLocalModelsHardwareSection()
        outerStack.addArrangedSubview(hardwareSection)

        scrollView.documentView = outerStack
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        refreshPythonStatus()

        return scrollView
    }

    private func detectPythonPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Try known search paths (ordered by preference)
        for path in PythonEnvironmentSupport.pythonSearchPaths(homeDirectoryPath: home) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Also try resolving via shell (user's login shell has full PATH)
        let shellProcess = Process()
        shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shellProcess.arguments = ["-l", "-c", "which python3"]
        let pipe = Pipe()
        shellProcess.standardOutput = pipe
        shellProcess.standardError = FileHandle.nullDevice
        do {
            try shellProcess.run()
            shellProcess.waitUntilExit()
            if shellProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {}

        return "/usr/bin/python3"
    }

    private func refreshPythonStatus() {
        let pythonPath = localModelsPythonPathField.stringValue
        Task {
            // First check if the Python binary actually exists
            let exists = FileManager.default.fileExists(atPath: pythonPath)
            guard exists else {
                await MainActor.run {
                    localModelsStatusDot.textColor = .systemRed
                    localModelsStatusLabel.stringValue = "Python not found at \(pythonPath)"
                }
                return
            }

            do {
                let packages = try localModelRunner?.checkPythonPackages(pythonPath: pythonPath) ?? [:]
                let missing = packages.filter { !$0.value }.map(\.key)
                await MainActor.run {
                    if missing.isEmpty {
                        localModelsStatusDot.textColor = .systemGreen
                        localModelsStatusLabel.stringValue = "Python ready \u{2014} transformers, torch installed"
                    } else {
                        localModelsStatusDot.textColor = .systemOrange
                        localModelsStatusLabel.stringValue = "Missing packages: \(missing.joined(separator: ", "))"
                    }
                }
            } catch let error as LocalModelRunnerError {
                await MainActor.run {
                    switch error {
                    case .scriptNotFound:
                        localModelsStatusDot.textColor = .systemRed
                        localModelsStatusLabel.stringValue = "Inference script not found in app bundle"
                    case .processExitedWithError(let code):
                        localModelsStatusDot.textColor = .systemOrange
                        localModelsStatusLabel.stringValue = "Python check failed (exit \(code)) \u{2014} packages may be broken"
                    default:
                        localModelsStatusDot.textColor = .systemRed
                        localModelsStatusLabel.stringValue = "Python check error: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    localModelsStatusDot.textColor = .systemRed
                    localModelsStatusLabel.stringValue = "Python check error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func buildLocalModelsPythonSection(config: AppConfig) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "PYTHON ENVIRONMENT")
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = SettingsLayoutSupport.groupCornerRadius
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 10
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        // Status line
        let statusStack = NSStackView()
        statusStack.orientation = .horizontal
        statusStack.spacing = 6
        localModelsStatusDot.font = .systemFont(ofSize: 10)
        localModelsStatusDot.textColor = .systemGray
        localModelsStatusLabel.font = .systemFont(ofSize: 12)
        localModelsStatusLabel.textColor = .secondaryLabelColor
        localModelsStatusLabel.stringValue = "Checking Python..."
        statusStack.addArrangedSubview(localModelsStatusDot)
        statusStack.addArrangedSubview(localModelsStatusLabel)
        cardStack.addArrangedSubview(statusStack)

        // Python path field
        let pathStack = NSStackView()
        pathStack.orientation = .horizontal
        pathStack.spacing = 8
        let pathLabel = NSTextField(labelWithString: "Python path:")
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.setContentHuggingPriority(.required, for: .horizontal)
        localModelsPythonPathField.stringValue = config.localModelPythonPath.isEmpty
            ? detectPythonPath() : config.localModelPythonPath
        localModelsPythonPathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        localModelsPythonPathField.placeholderString = "Auto-detect"
        localModelsPythonPathField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            localModelsPythonPathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
        pathStack.addArrangedSubview(pathLabel)
        pathStack.addArrangedSubview(localModelsPythonPathField)
        cardStack.addArrangedSubview(pathStack)

        // Install packages button
        let installBtn = NSButton(title: "Install Packages (pip install transformers torch)", target: self, action: #selector(installPythonPackagesClicked(_:)))
        installBtn.bezelStyle = .rounded
        installBtn.font = .systemFont(ofSize: 11)
        cardStack.addArrangedSubview(installBtn)

        if let cardContent = card.contentView {
            cardContent.addSubview(cardStack)
            NSLayoutConstraint.activate([
                cardStack.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 14),
                cardStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 16),
                cardStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -16),
                cardStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -14),
            ])
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: SettingsLayoutSupport.windowWidth - 40),
        ])

        return container
    }

    private func buildLocalModelsModelSection(config: AppConfig) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "AVAILABLE MODELS")
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = SettingsLayoutSupport.groupCornerRadius
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 4
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        // Header row
        let headerRow = makeModelRow(
            name: "Model", params: "Params", disk: "Disk", status: "Status",
            isHeader: true, repoID: "", isActive: false
        )
        cardStack.addArrangedSubview(headerRow)

        // Model rows
        localModelsModelRows = NSStackView()
        localModelsModelRows.orientation = .vertical
        localModelsModelRows.spacing = 2
        refreshModelRows(config: config)
        cardStack.addArrangedSubview(localModelsModelRows)

        // Test Inference
        let testBtn = NSButton(title: "Test Inference", target: self, action: #selector(testInferenceClicked(_:)))
        testBtn.bezelStyle = .rounded
        testBtn.font = .systemFont(ofSize: 11)
        cardStack.addArrangedSubview(testBtn)

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        cardStack.addArrangedSubview(sep)

        // Add custom model
        let customStack = NSStackView()
        customStack.orientation = .horizontal
        customStack.spacing = 8
        let customLabel = NSTextField(labelWithString: "Add Custom Model:")
        customLabel.font = .systemFont(ofSize: 11)
        customLabel.setContentHuggingPriority(.required, for: .horizontal)
        let customField = NSTextField(string: "")
        customField.placeholderString = "org/model or https://huggingface.co/org/model"
        customField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.tag = 9990
        NSLayoutConstraint.activate([
            customField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])
        let addBtn = NSButton(title: "Add", target: self, action: #selector(addCustomModelClicked(_:)))
        addBtn.bezelStyle = .rounded
        addBtn.font = .systemFont(ofSize: 11)
        customStack.addArrangedSubview(customLabel)
        customStack.addArrangedSubview(customField)
        customStack.addArrangedSubview(addBtn)
        cardStack.addArrangedSubview(customStack)

        if let cardContent = card.contentView {
            cardContent.addSubview(cardStack)
            NSLayoutConstraint.activate([
                cardStack.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 14),
                cardStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 16),
                cardStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -16),
                cardStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -14),
            ])
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: SettingsLayoutSupport.windowWidth - 40),
        ])

        return container
    }

    private func buildLocalModelsHardwareSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "HARDWARE")
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = SettingsLayoutSupport.groupCornerRadius
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        let hw = LocalModelRunner().gatherHardwareInfo()
        let ramGB = String(format: "%.1f", Double(hw.totalRAMBytes) / 1_073_741_824.0)
        let diskGB = String(format: "%.1f", Double(hw.availableDiskBytes) / 1_073_741_824.0)

        let ramLabel = NSTextField(labelWithString: "RAM: \(ramGB) GB total")
        ramLabel.font = .systemFont(ofSize: 12)
        cardStack.addArrangedSubview(ramLabel)

        let diskLabel = NSTextField(labelWithString: "Disk: \(diskGB) GB available")
        diskLabel.font = .systemFont(ofSize: 12)
        cardStack.addArrangedSubview(diskLabel)

        let archLabel = NSTextField(labelWithString: "Architecture: \(hw.architecture == "arm64" ? "Apple Silicon" : hw.architecture)")
        archLabel.font = .systemFont(ofSize: 12)
        cardStack.addArrangedSubview(archLabel)

        if let cardContent = card.contentView {
            cardContent.addSubview(cardStack)
            NSLayoutConstraint.activate([
                cardStack.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 14),
                cardStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 16),
                cardStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -16),
                cardStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -14),
            ])
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: SettingsLayoutSupport.windowWidth - 40),
        ])

        return container
    }

    private func refreshModelRows(config: AppConfig) {
        localModelsModelRows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Determine which models are actually downloaded
        let modelsDir = LocalModelSupport.modelsDirectoryURL(baseDirectoryURL: configManager.baseDirectoryURL)
        var downloadedSet = Set<String>()
        for model in LocalModelSupport.recommendedModels {
            let modelDir = LocalModelSupport.modelDirectoryURL(
                baseDirectoryURL: configManager.baseDirectoryURL, repoID: model.repoID
            )
            if FileManager.default.fileExists(atPath: modelDir.path) {
                downloadedSet.insert(model.repoID)
            }
        }

        // Parse custom models
        var savedCustom: [LocalModelEntry] = []
        if let data = config.localModelCustomModels.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([LocalModelEntry].self, from: data) {
            savedCustom = decoded
            for custom in savedCustom {
                let dir = LocalModelSupport.modelDirectoryURL(
                    baseDirectoryURL: configManager.baseDirectoryURL, repoID: custom.repoID
                )
                if FileManager.default.fileExists(atPath: dir.path) {
                    downloadedSet.insert(custom.repoID)
                }
            }
        }

        let merged = LocalModelSupport.mergedModelList(saved: savedCustom, downloaded: downloadedSet)

        for entry in merged {
            let isActive = entry.repoID == config.localModelRepoID
            let row = makeModelRow(
                name: entry.displayName, params: entry.parameterCount,
                disk: String(format: "%.1f GB", entry.approxDiskGB),
                status: entry.status == .ready ? "Ready" : "Not downloaded",
                isHeader: false, repoID: entry.repoID, isActive: isActive
            )
            localModelsModelRows.addArrangedSubview(row)
        }
    }

    private func makeModelRow(
        name: String, params: String, disk: String, status: String,
        isHeader: Bool, repoID: String, isActive: Bool
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([nameLabel.widthAnchor.constraint(equalToConstant: 120)])

        let paramsLabel = NSTextField(labelWithString: params)
        paramsLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        paramsLabel.textColor = .secondaryLabelColor
        paramsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([paramsLabel.widthAnchor.constraint(equalToConstant: 60)])

        let diskLabel = NSTextField(labelWithString: disk)
        diskLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        diskLabel.textColor = .secondaryLabelColor
        diskLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([diskLabel.widthAnchor.constraint(equalToConstant: 60)])

        let statusLabel = NSTextField(labelWithString: status)
        statusLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        statusLabel.textColor = status == "Ready" ? .systemGreen : .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([statusLabel.widthAnchor.constraint(equalToConstant: 100)])

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(paramsLabel)
        row.addArrangedSubview(diskLabel)
        row.addArrangedSubview(statusLabel)

        if !isHeader {
            if status == "Ready" {
                let selectBtn = NSButton(
                    checkboxWithTitle: isActive ? "Active" : "Select",
                    target: self, action: #selector(selectModelClicked(_:))
                )
                selectBtn.state = isActive ? .on : .off
                selectBtn.identifier = NSUserInterfaceItemIdentifier(repoID)
                selectBtn.font = .systemFont(ofSize: 10)
                row.addArrangedSubview(selectBtn)

                let deleteBtn = NSButton(title: "Delete", target: self, action: #selector(deleteModelClicked(_:)))
                deleteBtn.bezelStyle = .rounded
                deleteBtn.font = .systemFont(ofSize: 10)
                deleteBtn.identifier = NSUserInterfaceItemIdentifier(repoID)
                row.addArrangedSubview(deleteBtn)
            } else {
                let pullBtn = NSButton(title: "Pull", target: self, action: #selector(pullModelClicked(_:)))
                pullBtn.bezelStyle = .rounded
                pullBtn.font = .systemFont(ofSize: 10)
                pullBtn.identifier = NSUserInterfaceItemIdentifier(repoID)
                row.addArrangedSubview(pullBtn)
            }
        }

        return row
    }

    @objc private func installPythonPackagesClicked(_ sender: NSButton) {
        let pythonPath = localModelsPythonPathField.stringValue
        let cmd = PythonEnvironmentSupport.pipInstallCommand(pythonPath: pythonPath)
        localModelsStatusLabel.stringValue = "Installing packages..."
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            try? process.run()
            process.waitUntilExit()
            await MainActor.run {
                if process.terminationStatus == 0 {
                    localModelsStatusLabel.stringValue = "Packages installed successfully"
                } else {
                    localModelsStatusLabel.stringValue = "Package installation failed (exit \(process.terminationStatus))"
                }
            }
        }
    }

    @objc private func pullModelClicked(_ sender: NSButton) {
        guard let repoID = sender.identifier?.rawValue, !repoID.isEmpty else { return }
        let config = configManager.loadConfig()
        let destPath = LocalModelSupport.modelDirectoryURL(
            baseDirectoryURL: configManager.baseDirectoryURL, repoID: repoID
        ).path
        let pythonPath = config.localModelPythonPath.isEmpty
            ? localModelsPythonPathField.stringValue : config.localModelPythonPath
        sender.isEnabled = false
        sender.title = "Pulling..."

        Task {
            do {
                try (self.localModelRunner ?? LocalModelRunner()).downloadModel(
                    repoID: repoID, destPath: destPath, pythonPath: pythonPath,
                    onProgress: { line in
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? String {
                            DispatchQueue.main.async { sender.title = message }
                        }
                    }
                )
                await MainActor.run {
                    sender.title = "Done"
                    self.refreshModelRows(config: self.configManager.loadConfig())
                }
            } catch {
                await MainActor.run {
                    sender.isEnabled = true
                    sender.title = "Pull"
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    @objc private func selectModelClicked(_ sender: NSButton) {
        guard let repoID = sender.identifier?.rawValue else { return }
        var config = configManager.loadConfig()
        config.localModelRepoID = sender.state == .on ? repoID : ""
        try? configManager.saveConfig(config)
        onConfigSaved(config)
        refreshModelRows(config: config)
    }

    @objc private func deleteModelClicked(_ sender: NSButton) {
        guard let repoID = sender.identifier?.rawValue else { return }
        let modelDir = LocalModelSupport.modelDirectoryURL(
            baseDirectoryURL: configManager.baseDirectoryURL, repoID: repoID
        )
        try? FileManager.default.removeItem(at: modelDir)
        var config = configManager.loadConfig()
        if config.localModelRepoID == repoID {
            config.localModelRepoID = ""
            try? configManager.saveConfig(config)
            onConfigSaved(config)
        }
        refreshModelRows(config: configManager.loadConfig())
    }

    @objc private func addCustomModelClicked(_ sender: NSButton) {
        guard let parentStack = sender.superview as? NSStackView else { return }
        let customField = parentStack.arrangedSubviews.first(where: { $0.tag == 9990 }) as? NSTextField
        guard let input = customField?.stringValue, !input.isEmpty else { return }
        guard let repoID = LocalModelSupport.extractRepoID(from: input) else {
            let alert = NSAlert()
            alert.messageText = "Invalid Model"
            alert.informativeText = "Enter a valid Hugging Face repo ID (org/model) or URL."
            alert.runModal()
            return
        }

        var config = configManager.loadConfig()
        var customModels: [LocalModelEntry] = []
        if let data = config.localModelCustomModels.data(using: .utf8) {
            customModels = (try? JSONDecoder().decode([LocalModelEntry].self, from: data)) ?? []
        }
        guard !customModels.contains(where: { $0.repoID == repoID }) else { return }

        let entry = LocalModelEntry(
            repoID: repoID,
            displayName: repoID.components(separatedBy: "/").last ?? repoID,
            parameterCount: "?",
            approxDiskGB: 0
        )
        customModels.append(entry)
        if let encoded = try? JSONEncoder().encode(customModels),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            config.localModelCustomModels = jsonStr
            try? configManager.saveConfig(config)
        }
        customField?.stringValue = ""
        refreshModelRows(config: configManager.loadConfig())
    }

    @objc private func testInferenceClicked(_ sender: NSButton) {
        let config = configManager.loadConfig()
        guard !config.localModelRepoID.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Model Selected"
            alert.informativeText = "Select a downloaded model first."
            alert.runModal()
            return
        }
        let modelPath = LocalModelSupport.modelDirectoryURL(
            baseDirectoryURL: configManager.baseDirectoryURL, repoID: config.localModelRepoID
        ).path
        let pythonPath = config.localModelPythonPath.isEmpty
            ? localModelsPythonPathField.stringValue : config.localModelPythonPath
        sender.isEnabled = false
        sender.title = "Testing..."
        Task {
            do {
                let result = try localModelRunner?.correctText(
                    "Fix grammatical errors in this sentence: She go to the store yesterday and buyed some food.",
                    modelPath: modelPath, pythonPath: pythonPath, timeoutSeconds: 120
                ) ?? ""
                await MainActor.run {
                    sender.isEnabled = true
                    sender.title = "Test Inference"
                    let alert = NSAlert()
                    alert.messageText = "Test Result"
                    alert.informativeText = result
                    alert.runModal()
                }
            } catch {
                await MainActor.run {
                    sender.isEnabled = true
                    sender.title = "Test Inference"
                    let alert = NSAlert()
                    alert.messageText = "Test Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func buildCorrectionModesSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Section header
        let header = NSTextField(labelWithString: "CORRECTION MODES")
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = SettingsLayoutSupport.groupCornerRadius
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        // Build comparison table
        let tableStack = NSStackView()
        tableStack.orientation = .vertical
        tableStack.spacing = 0
        tableStack.translatesAutoresizingMaskIntoConstraints = false

        let colWidths: (feature: CGFloat, local: CGFloat, llm: CGFloat) = (80, 145, 170)

        // Detect local model configuration
        let hasLocalModel = !configManager.loadConfig().localModelRepoID.isEmpty

        // Header row
        let headerRow = makeComparisonRow(
            feature: "Feature", local: "\u{2318}E Local", llm: "\u{2318}\u{21E7}E LLM",
            widths: colWidths, isHeader: true
        )
        tableStack.addArrangedSubview(headerRow)

        // Data rows
        let rows: [(String, String, String)] = [
            ("Speed", hasLocalModel ? "2–10 seconds" : "Instant", "2–5 seconds"),
            ("Network", "None (offline)", "Requires AI CLI"),
            ("Spelling", "Yes", "Yes"),
            ("Grammar",
             hasLocalModel ? "Yes (Local Model)" : "Basic (Harper)",
             "Yes (contextual)"),
            ("Punctuation",
             hasLocalModel ? "Yes (Local Model)" : "No",
             "Yes"),
            ("Rewrites", hasLocalModel ? "Light corrections" : "Light corrections", "Full restructuring"),
        ]

        for (index, row) in rows.enumerated() {
            let rowView = makeComparisonRow(
                feature: row.0, local: row.1, llm: row.2,
                widths: colWidths, isHeader: false
            )
            if index % 2 == 0 {
                let bg = NSView()
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
                bg.translatesAutoresizingMaskIntoConstraints = false
                rowView.addSubview(bg, positioned: .below, relativeTo: nil)
                NSLayoutConstraint.activate([
                    bg.topAnchor.constraint(equalTo: rowView.topAnchor),
                    bg.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
                    bg.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
                    bg.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
                ])
            }
            tableStack.addArrangedSubview(rowView)
        }

        // Engine status
        let engineStack = NSStackView()
        engineStack.orientation = .horizontal
        engineStack.spacing = 6
        engineStack.alignment = .firstBaseline
        engineStack.translatesAutoresizingMaskIntoConstraints = false

        let dotView = NSTextField(labelWithString: "\u{25CF}")
        dotView.font = .systemFont(ofSize: 10)

        let engineLabel = NSTextField(labelWithString: "")
        engineLabel.font = .systemFont(ofSize: 11)
        engineLabel.textColor = .secondaryLabelColor
        engineLabel.lineBreakMode = .byWordWrapping
        engineLabel.maximumNumberOfLines = 2
        engineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if hasLocalModel {
            let modelName = configManager.loadConfig().localModelRepoID
            dotView.textColor = .systemGreen
            engineLabel.stringValue = "Local engine: \(modelName) (Hugging Face)"
        } else {
            dotView.textColor = .systemOrange
            engineLabel.stringValue = "Local engine: Harper + NSSpellChecker (no local model) — configure in Settings > Local Models"
        }

        engineStack.addArrangedSubview(dotView)
        engineStack.addArrangedSubview(engineLabel)

        // Assemble card content
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.addArrangedSubview(tableStack)
        cardStack.addArrangedSubview(engineStack)

        if let cardContent = card.contentView {
            cardContent.addSubview(cardStack)
            NSLayoutConstraint.activate([
                cardStack.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 14),
                cardStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 16),
                cardStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -16),
                cardStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -14),
            ])
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeComparisonRow(
        feature: String, local: String, llm: String,
        widths: (feature: CGFloat, local: CGFloat, llm: CGFloat),
        isHeader: Bool
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        let font: NSFont = isHeader
            ? .systemFont(ofSize: 11, weight: .semibold)
            : .systemFont(ofSize: 11)
        let color: NSColor = isHeader ? .secondaryLabelColor : .labelColor

        func makeCell(_ text: String, width: CGFloat) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = font
            label.textColor = color
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
            return label
        }

        let featureCell = makeCell(feature, width: widths.feature)
        let localCell = makeCell(local, width: widths.local)
        let llmCell = makeCell(llm, width: widths.llm)

        row.addArrangedSubview(featureCell)
        row.addArrangedSubview(localCell)
        row.addArrangedSubview(llmCell)

        // Vertical padding
        let padding: CGFloat = isHeader ? 6 : 4
        row.edgeInsets = NSEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)

        return row
    }

    private func buildGeneralTab() -> NSView {
        providerPopup.removeAllItems()
        providerOptions.forEach { providerPopup.addItem(withTitle: $0.displayName) }
        providerPopup.target = self
        providerPopup.action = #selector(providerPopupChanged)
        modelPopup.target = self
        modelPopup.action = #selector(modelPopupChanged)

        customModelField.placeholderString = "Enter custom model name"
        customModelContainer.orientation = .horizontal
        customModelContainer.spacing = 8
        customModelContainer.alignment = .firstBaseline
        customModelContainer.addArrangedSubview(makeFieldLabel("Custom"))
        customModelContainer.addArrangedSubview(customModelField)

        languagePopup.removeAllItems()
        AppConfig.supportedLanguages.forEach { languagePopup.addItem(withTitle: $0.displayName) }
        tonePresetPopup.removeAllItems()
        AppConfig.supportedPresets.forEach { tonePresetPopup.addItem(withTitle: $0.capitalized) }

        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.maximumNumberOfLines = 3
        hintLabel.lineBreakMode = .byWordWrapping

        let providerDesc = makeDescription("The AI provider used for grammar corrections")
        let modelDesc = makeDescription(modelDescriptionText())
        modelDesc.identifier = NSUserInterfaceItemIdentifier("modelDescriptionLabel")

        let languageDesc = makeDescription("Auto-detect works for most languages")
        let toneDesc = makeDescription("Adjusts formality and style of corrections")

        let stack = makeTabStack(sections: [
            buildCorrectionModesSection(),
            makeSection(title: "Provider & Model", views: [
                makeRow(label: makeFieldLabel("Provider"), field: providerPopup),
                providerDesc,
                makeRow(label: makeFieldLabel("Model"), field: modelPopup),
                modelDesc,
                customModelContainer,
                hintLabel,
            ]),
            makeSection(title: "Language & Tone", views: [
                makeRow(label: makeFieldLabel("Language"), field: languagePopup),
                languageDesc,
                makeRow(label: makeFieldLabel("Tone"), field: tonePresetPopup),
                toneDesc,
            ]),
            makeButtonRow(),
        ])
        return stack
    }

    private func modelDescriptionText() -> String {
        guard let selected = modelPopup.selectedItem?.title else { return "" }
        let descriptions: [String: String] = [
            "Sonnet": "Balanced speed and quality",
            "Opus": "Highest quality, slower",
            "Haiku": "Fastest, lightweight corrections",
            "GPT-4o": "OpenAI flagship model",
            "GPT-4o mini": "Fast and cost-effective",
            "o3-mini": "OpenAI reasoning model",
            "Gemini 2.0 Flash": "Fast multimodal model",
            "Gemini 2.5 Pro": "Most capable Gemini model",
            "Custom...": "Specify any model identifier",
        ]
        return descriptions[selected] ?? ""
    }

    private func refreshModelDescription() {
        guard let tabView = tabViews[.general] else { return }
        func findLabel(in view: NSView) -> NSTextField? {
            if let label = view as? NSTextField,
               label.identifier?.rawValue == "modelDescriptionLabel" {
                return label
            }
            for sub in view.subviews {
                if let found = findLabel(in: sub) { return found }
            }
            return nil
        }
        if let label = findLabel(in: tabView) {
            label.stringValue = modelDescriptionText()
        }
    }

    private func buildHotkeyTab() -> NSView {
        hotkeyKeyPopup.removeAllItems()
        hotkeyKeyOptions.forEach { hotkeyKeyPopup.addItem(withTitle: $0.title) }
        hotkeyKeyPopup.target = self
        hotkeyKeyPopup.action = #selector(hotkeyInputChanged)

        commandModifierCheckbox.target = self
        commandModifierCheckbox.action = #selector(hotkeyInputChanged)
        optionModifierCheckbox.target = self
        optionModifierCheckbox.action = #selector(hotkeyInputChanged)
        controlModifierCheckbox.target = self
        controlModifierCheckbox.action = #selector(hotkeyInputChanged)
        shiftModifierCheckbox.target = self
        shiftModifierCheckbox.action = #selector(hotkeyInputChanged)

        let modStack = NSStackView()
        modStack.orientation = .horizontal
        modStack.spacing = 6
        modStack.addArrangedSubview(commandModifierCheckbox)
        modStack.addArrangedSubview(optionModifierCheckbox)
        modStack.addArrangedSubview(controlModifierCheckbox)
        modStack.addArrangedSubview(shiftModifierCheckbox)

        hotkeyPreviewLabel.textColor = .secondaryLabelColor
        hotkeyPreviewLabel.font = .systemFont(ofSize: 12, weight: .medium)

        hotkeyBadgeView.wantsLayer = true
        hotkeyBadgeView.layer?.cornerRadius = 6
        hotkeyBadgeView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        hotkeyBadgeView.layer?.borderWidth = 1
        hotkeyBadgeView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        hotkeyBadgeView.translatesAutoresizingMaskIntoConstraints = false

        hotkeyBadgeLabel.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        hotkeyBadgeLabel.textColor = .controlAccentColor
        hotkeyBadgeLabel.alignment = .center
        hotkeyBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        hotkeyBadgeView.addSubview(hotkeyBadgeLabel)

        NSLayoutConstraint.activate([
            hotkeyBadgeLabel.topAnchor.constraint(equalTo: hotkeyBadgeView.topAnchor, constant: 8),
            hotkeyBadgeLabel.bottomAnchor.constraint(equalTo: hotkeyBadgeView.bottomAnchor, constant: -8),
            hotkeyBadgeLabel.leadingAnchor.constraint(equalTo: hotkeyBadgeView.leadingAnchor, constant: 16),
            hotkeyBadgeLabel.trailingAnchor.constraint(equalTo: hotkeyBadgeView.trailingAnchor, constant: -16),
        ])

        let badgeRow = NSStackView()
        badgeRow.orientation = .horizontal
        badgeRow.spacing = 8
        badgeRow.alignment = .centerY
        badgeRow.addArrangedSubview(makeFieldLabel("Current"))
        badgeRow.addArrangedSubview(hotkeyBadgeView)

        let stack = makeTabStack(sections: [
            makeSection(title: "Keyboard Shortcut", views: [
                badgeRow,
                makeRow(label: makeFieldLabel("Key"), field: hotkeyKeyPopup),
                makeRow(label: makeFieldLabel("Modifiers"), field: modStack),
                hotkeyPreviewLabel,
            ]),
            makeButtonRow(),
        ])
        return stack
    }

    private func buildBehaviorTab() -> NSView {
        showDiffPreviewCheckbox.setContentHuggingPriority(.required, for: .vertical)
        clipboardOnlyModeCheckbox.setContentHuggingPriority(.required, for: .vertical)
        soundFeedbackCheckbox.setContentHuggingPriority(.required, for: .vertical)
        notifyOnSuccessCheckbox.setContentHuggingPriority(.required, for: .vertical)
        liveFeedbackCheckbox.setContentHuggingPriority(.required, for: .vertical)
        launchAtLoginCheckbox.setContentHuggingPriority(.required, for: .vertical)
        diffPreviewDurationField.placeholderString = "3"
        diffPreviewDurationField.alignment = .left

        let durationDesc = makeDescription("Seconds to show the diff popup before auto-dismissing (1–30)")

        let stack = makeTabStack(sections: [
            makeSection(title: "Correction", views: [
                makeCheckboxWithDescription(
                    checkbox: showDiffPreviewCheckbox,
                    description: "Shows a side-by-side diff before replacing text"
                ),
                makeCheckboxWithDescription(
                    checkbox: clipboardOnlyModeCheckbox,
                    description: "Corrected text is copied but not auto-pasted"
                ),
                makeRow(label: makeFieldLabel("Popup duration (s)"), field: diffPreviewDurationField),
                durationDesc,
            ]),
            makeSection(title: "Live Feedback", views: [
                makeCheckboxWithDescription(
                    checkbox: liveFeedbackCheckbox,
                    description: "Monitors the active text field and highlights spelling issues in real time using macOS spell checker"
                ),
            ]),
            makeSection(title: "Feedback", views: [
                makeCheckboxWithDescription(
                    checkbox: soundFeedbackCheckbox,
                    description: "Plays a system sound when a correction finishes"
                ),
                makeCheckboxWithDescription(
                    checkbox: notifyOnSuccessCheckbox,
                    description: "Shows a macOS notification banner on success"
                ),
            ]),
            makeSection(title: "System", views: [
                makeSwitchRow(
                    label: "Launch at Login",
                    toggle: launchAtLoginSwitch,
                    description: "Start GhostEdit automatically when you log in"
                ),
            ]),
            makeButtonRow(),
        ])
        return stack
    }

    private func buildAdvancedTab() -> NSView {
        historyLimitField.placeholderString = "50"
        historyLimitField.alignment = .left
        timeoutField.placeholderString = "60"
        timeoutField.alignment = .left
        developerModeCheckbox.setContentHuggingPriority(.required, for: .vertical)

        let historyDesc = makeDescription("Maximum number of corrections to keep in history")
        let timeoutDesc = makeDescription("Seconds to wait before cancelling a correction request")

        let stack = makeTabStack(sections: [
            makeSection(title: "Limits", views: [
                makeRow(label: makeFieldLabel("History limit"), field: historyLimitField),
                historyDesc,
                makeRow(label: makeFieldLabel("Timeout (s)"), field: timeoutField),
                timeoutDesc,
            ]),
            makeSection(title: "Debug", views: [
                makeCheckboxWithDescription(
                    checkbox: developerModeCheckbox,
                    description: "Shows a console log with CLI commands and raw responses"
                ),
            ]),
            makeButtonRow(),
        ])
        return stack
    }

    // MARK: - Layout Helpers

    private func makeTabStack(sections: [NSView]) -> NSView {
        // Separate the button row (last item) from content sections
        let contentSections: [NSView]
        let buttonRow: NSView?
        if let last = sections.last, last is NSStackView,
           (last as? NSStackView)?.arrangedSubviews.contains(where: { ($0 as? NSButton)?.title == "Save" }) == true {
            contentSections = Array(sections.dropLast())
            buttonRow = last
        } else {
            contentSections = sections
            buttonRow = nil
        }

        let contentStack = NSStackView(views: contentSections)
        contentStack.orientation = .vertical
        contentStack.spacing = SettingsLayoutSupport.sectionSpacing
        contentStack.alignment = .leading
        contentStack.edgeInsets = NSEdgeInsets(
            top: SettingsLayoutSupport.verticalInset,
            left: 32,
            bottom: SettingsLayoutSupport.verticalInset,
            right: 32
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        for section in contentSections {
            section.translatesAutoresizingMaskIntoConstraints = false
            section.widthAnchor.constraint(
                equalToConstant: SettingsLayoutSupport.windowWidth - 64
            ).isActive = true
        }

        guard let buttonRow = buttonRow else { return contentStack }

        // Container: content pinned to top, button row pinned to bottom
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(contentStack)
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: container.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -SettingsLayoutSupport.verticalInset),
            buttonRow.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: SettingsLayoutSupport.sectionSpacing),
        ])

        return container
    }

    private func makeSection(title: String, views: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title.uppercased())
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = SettingsLayoutSupport.groupCornerRadius
        card.fillColor = .controlBackgroundColor
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = SettingsLayoutSupport.rowSpacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let cardContent = card.contentView {
            cardContent.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 14),
                stack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -16),
                stack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -14),
            ])
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeButtonRow() -> NSView {
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(buttonSpacer)
        buttonRow.addArrangedSubview(closeButton)
        buttonRow.addArrangedSubview(saveButton)
        return buttonRow
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: SettingsLayoutSupport.labelWidth).isActive = true
        return label
    }

    private func makeRow(label: NSTextField, field: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        return row
    }

    private func makeDescription(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeSwitchRow(label: String, toggle: NSSwitch, description: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 13)
        row.addArrangedSubview(labelField)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(toggle)

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 2
        container.alignment = .leading
        container.addArrangedSubview(row)

        let desc = makeDescription(description)
        container.addArrangedSubview(desc)

        return container
    }

    private func makeCheckboxWithDescription(checkbox: NSButton, description: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.addArrangedSubview(checkbox)
        let desc = makeDescription(description)
        desc.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(desc)
        // Indent description to align with checkbox label
        desc.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20).isActive = true
        return stack
    }

    // MARK: - Load / Save

    private func loadCurrentValues() {
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let providerIndex = providerOptions.firstIndex(of: provider) ?? 0
        providerPopup.selectItem(at: providerIndex)
        launchAtLoginCheckbox.state = config.launchAtLogin ? .on : .off
        launchAtLoginSwitch.state = config.launchAtLogin ? .on : .off
        soundFeedbackCheckbox.state = config.soundFeedbackEnabled ? .on : .off
        notifyOnSuccessCheckbox.state = config.notifyOnSuccess ? .on : .off
        clipboardOnlyModeCheckbox.state = config.clipboardOnlyMode ? .on : .off
        showDiffPreviewCheckbox.state = config.showDiffPreview ? .on : .off
        liveFeedbackCheckbox.state = config.liveFeedbackEnabled ? .on : .off
        if let toneIndex = AppConfig.supportedPresets.firstIndex(of: config.tonePreset) {
            tonePresetPopup.selectItem(at: toneIndex)
        } else {
            tonePresetPopup.selectItem(at: 0)
        }
        developerModeCheckbox.state = config.developerMode ? .on : .off
        if let langIndex = AppConfig.supportedLanguages.firstIndex(where: { $0.code == config.resolvedLanguage }) {
            languagePopup.selectItem(at: langIndex)
        } else {
            languagePopup.selectItem(at: 0) // auto
        }
        historyLimitField.stringValue = "\(config.historyLimit)"
        timeoutField.stringValue = "\(config.timeoutSeconds)"
        diffPreviewDurationField.stringValue = "\(config.diffPreviewDuration)"
        loadHotkeyValues(from: config)

        let rawModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = rawModel.isEmpty ? AppConfig.defaultModel(for: provider) : rawModel
        reloadModelOptions(for: provider, selectedModel: selectedModel)
    }

    @objc private func providerPopupChanged() {
        let provider = selectedProvider()
        reloadModelOptions(for: provider, selectedModel: AppConfig.defaultModel(for: provider))
    }

    @objc private func modelPopupChanged() {
        refreshCustomFieldVisibility()
        refreshModelDescription()
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
        refreshModelDescription()
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
            hotkeyBadgeLabel.stringValue = "—"
            return
        }

        let modifiers = selectedHotkeyModifiers()
        let display = HotkeySupport.displayString(keyCode: keyCode, modifiers: modifiers)
        hotkeyPreviewLabel.stringValue = "Current hotkey: \(display)"
        hotkeyBadgeLabel.stringValue = display
    }

    private func refreshCustomFieldVisibility() {
        let isCustom = selectedOptionValue() == nil
        customModelContainer.isHidden = !isCustom
        if isCustom {
            customModelField.becomeFirstResponder()
        }
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
        let durationText = diffPreviewDurationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let diffPreviewDuration = Int(durationText), diffPreviewDuration >= 1, diffPreviewDuration <= 30 else {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Popup duration is invalid"
            alert.informativeText = "Enter a whole number between 1 and 30 for popup duration."
            alert.runModal()
            return
        }

        var config = configManager.loadConfig()
        config.provider = provider.rawValue
        config.model = model
        config.hotkeyKeyCode = hotkeyKeyCode
        config.hotkeyModifiers = hotkeyModifiers
        config.launchAtLogin = (launchAtLoginSwitch.state == .on)
        config.soundFeedbackEnabled = (soundFeedbackCheckbox.state == .on)
        config.notifyOnSuccess = (notifyOnSuccessCheckbox.state == .on)
        config.clipboardOnlyMode = (clipboardOnlyModeCheckbox.state == .on)
        config.showDiffPreview = (showDiffPreviewCheckbox.state == .on)
        config.liveFeedbackEnabled = (liveFeedbackCheckbox.state == .on)
        let toneIndex = tonePresetPopup.indexOfSelectedItem
        config.tonePreset = AppConfig.supportedPresets.indices.contains(toneIndex)
            ? AppConfig.supportedPresets[toneIndex]
            : "default"
        config.developerMode = (developerModeCheckbox.state == .on)
        let langIndex = languagePopup.indexOfSelectedItem
        config.language = AppConfig.supportedLanguages.indices.contains(langIndex)
            ? AppConfig.supportedLanguages[langIndex].code
            : "auto"
        config.historyLimit = historyLimit
        config.timeoutSeconds = timeoutSeconds
        config.diffPreviewDuration = diffPreviewDuration

        // Local Models tab: save python path override
        let pythonPathValue = localModelsPythonPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.localModelPythonPath = pythonPathValue == "/usr/bin/python3" ? "" : pythonPathValue

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
            showSaveConfirmation()
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

    private func showSaveConfirmation() {
        guard let window else {
            close()
            return
        }

        // Show a brief "Settings Saved" overlay before closing
        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        overlay.layer?.cornerRadius = 8
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSTextField(labelWithString: "\u{2713} Settings Saved")
        checkmark.font = .systemFont(ofSize: 14, weight: .semibold)
        checkmark.textColor = .white
        checkmark.alignment = .center
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(checkmark)

        guard let contentView = window.contentView else {
            close()
            return
        }
        contentView.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 12),
            checkmark.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -12),
            checkmark.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 24),
            checkmark.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
        ])

        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            overlay.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                overlay.animator().alphaValue = 0
            }, completionHandler: {
                overlay.removeFromSuperview()
                self?.close()
            })
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

    private func applyContent(for state: HUDOverlayState) {
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
        case .fallback:
            tintColor = NSColor.systemOrange.withAlphaComponent(0.06)
        case .error:
            tintColor = NSColor.systemRed.withAlphaComponent(0.06)
        }
        tintOverlay?.layer?.backgroundColor = tintColor.cgColor
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
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        popoverDismissTimer?.invalidate()
        popoverDismissTimer = nil
        dismissWidget()
        dismissPopover()
        lastCheckedText = nil
        currentCheckedText = nil
        currentIssues = []
        currentFocusedPID = nil
        state = .idle
        isPolling = false
        isMouseInsidePopover = false
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

// MARK: - QuickFixDiffPopupController

final class QuickFixDiffPopupController: NSObject {
    static let autoDismissDelay: TimeInterval = 3.0
    static let popupWidth: CGFloat = 300
    static let popupMaxHeight: CGFloat = 120

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(segments: [DiffSegment], near element: AXUIElement, widgetFrame: NSRect?, duration: TimeInterval = QuickFixDiffPopupController.autoDismissDelay) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let newPanel = buildPanel(segments: segments)
        positionPanel(newPanel, near: element, widgetFrame: widgetFrame)

        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1
        }

        panel = newPanel

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let panel else { return }
        let fadeDuration: TimeInterval = 0.2

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }

    private func buildPanel(segments: [DiffSegment]) -> NSPanel {
        let panelWidth = Self.popupWidth

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: Self.popupMaxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hasShadow = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let effectView = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: panelWidth, height: Self.popupMaxHeight)
        )
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        let textField = NSTextField(wrappingLabelWithString: "")
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.translatesAutoresizingMaskIntoConstraints = false

        let attrString = NSMutableAttributedString()
        for segment in segments {
            let attrs: [NSAttributedString.Key: Any]
            switch segment.kind {
            case .equal:
                attrs = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor
                ]
            case .insertion:
                attrs = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            case .deletion:
                attrs = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.15),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
            }
            attrString.append(NSAttributedString(string: segment.text, attributes: attrs))
        }
        textField.attributedStringValue = attrString

        effectView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor, constant: -8)
        ])

        effectView.layoutSubtreeIfNeeded()
        let intrinsicHeight = textField.intrinsicContentSize.height + 16
        let panelHeight = min(intrinsicHeight, Self.popupMaxHeight)

        newPanel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        effectView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        newPanel.contentView = effectView

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        effectView.addGestureRecognizer(clickGesture)

        return newPanel
    }

    @objc private func handleClick() {
        dismiss()
    }

    private func positionPanel(_ panel: NSPanel, near element: AXUIElement, widgetFrame: NSRect?) {
        let panelSize = panel.frame.size
        guard let screen = NSScreen.main else { return }

        var targetOrigin: NSPoint

        if let wf = widgetFrame {
            // Position directly above the live feedback widget
            targetOrigin = NSPoint(x: wf.origin.x, y: wf.origin.y + wf.height + 4)
        } else {
            // Query AX element position/size to place near the text field
            var posValue: AnyObject?
            var szValue: AnyObject?
            let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
            let szResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &szValue)

            if posResult == .success, szResult == .success,
               let pv = posValue, let sv = szValue {
                var position = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &position)
                AXValueGetValue(sv as! AXValue, .cgSize, &size)

                // Convert from top-left screen coords to Cocoa bottom-left coords
                let screenHeight = screen.frame.height
                let fieldBottomY = screenHeight - (position.y + size.height)
                // Position below the text field
                targetOrigin = NSPoint(x: position.x, y: fieldBottomY - panelSize.height - 8)
            } else {
                // Fallback: bottom-right corner of screen
                let sf = screen.visibleFrame
                targetOrigin = NSPoint(x: sf.maxX - panelSize.width - 20, y: sf.minY + 20)
            }
        }

        let sf = screen.visibleFrame

        // Flip to above the field if below screen
        if targetOrigin.y < sf.minY {
            if let wf = widgetFrame {
                targetOrigin.y = wf.origin.y - panelSize.height - 4
            } else {
                targetOrigin.y = targetOrigin.y + panelSize.height + 8
            }
        }

        // Clamp X to screen bounds
        targetOrigin.x = max(sf.minX, min(targetOrigin.x, sf.maxX - panelSize.width))

        panel.setFrameOrigin(targetOrigin)
    }
}
