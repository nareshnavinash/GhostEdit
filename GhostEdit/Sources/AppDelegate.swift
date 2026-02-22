import AppKit
import ApplicationServices
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkeyManager = HotkeyManager()
    private let clipboardManager = ClipboardManager()
    private let configManager = ConfigManager()
    private lazy var shellRunner = ShellRunner(configManager: configManager)
    private var settingsWindowController: SettingsWindowController?

    private var statusMenu: NSMenu?
    private var statusMenuItem: NSMenuItem?
    private var runNowMenuItem: NSMenuItem?

    private var isProcessing = false
    private var isShowingAccessibilityAlert = false
    private var didShowAccessibilityGuidance = false
    private var clipboardSnapshot: ClipboardManager.Snapshot?
    private var targetAppAtTrigger: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?

    private let statusPrefix = "Status: "
    private let idleIcon = "ⓖ"
    private let workingIcon = "🤓"
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
        } catch {
            showFatalAlert(
                title: "GhostEdit Setup Failed",
                message: "Could not create ~/.ghostedit files.\n\n\(error.localizedDescription)"
            )
            return
        }

        startObservingActiveApplication()
        _ = ensureAccessibilityPermission(promptSystemDialog: true, showGuidanceAlert: false)
        syncLaunchAtLoginPreferenceSilently()
        registerHotkey()
        setStatus("Idle")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        stopProcessingIndicator()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            setMenuBarIcon(idleIcon)
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

        targetAppAtTrigger = targetApp
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: poll)
        }

        poll()
    }

    private func processSelectedText(_ selectedText: String) {
        let prompt: String
        let config = configManager.loadConfig()
        let provider = config.resolvedProvider
        let model = config.resolvedModel(for: provider)
        do {
            prompt = try configManager.loadPrompt()
        } catch {
            restoreClipboardSnapshot(after: 0)
            notifyFailure(body: "Correction Failed. Could not read prompt file.")
            setStatus("Failed to read prompt file")
            finishProcessing()
            return
        }

        let modelDisplay = model.isEmpty ? "provider default" : model
        setStatus("Processing with \(provider.executableName) (\(modelDisplay))...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let correctedText = try self.shellRunner.correctText(
                    systemPrompt: prompt,
                    selectedText: selectedText
                )

                DispatchQueue.main.async {
                    self.clipboardManager.writePlainText(correctedText)
                    self.targetAppAtTrigger?.activate(options: [.activateAllWindows])

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let pasted = self.clipboardManager.simulatePasteShortcut(using: .annotatedSession)
                            || self.clipboardManager.simulatePasteShortcut(using: .hidSystem)

                        if !pasted {
                            NSSound.beep()
                            self.notifyFailure(body: "Correction Failed. Could not paste corrected text.")
                            self.setStatus("Paste failed")
                        } else {
                            let time = self.timeFormatter.string(from: Date())
                            self.setStatus("Last correction succeeded at \(time)")
                        }

                        self.restoreClipboardSnapshot(after: 0.25)
                        self.finishProcessing()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.restoreClipboardSnapshot(after: 0)
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
    }

    private func startProcessingIndicator() {
        runNowMenuItem?.isEnabled = false
        statusMenu?.cancelTracking()
        statusItem.menu = nil
        setMenuBarIcon(workingIcon)
    }

    private func stopProcessingIndicator() {
        runNowMenuItem?.isEnabled = true
        statusItem.menu = statusMenu
        setMenuBarIcon(idleIcon)
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
            alert.informativeText = "Enable GhostEdit in System Settings > Privacy & Security > Accessibility so it can send Cmd+C and Cmd+V."
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

    private func setMenuBarIcon(_ icon: String) {
        guard let button = statusItem.button else {
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular)
        ]

        button.image = nil
        button.title = icon
        button.attributedTitle = NSAttributedString(string: icon, attributes: attrs)
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
                self.setStatus("Settings saved (\(provider.executableName), model: \(modelDisplay))")
            }
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let launchAtLogin = configManager.loadConfig().launchAtLogin
        try? LaunchAtLoginManager.setEnabled(launchAtLogin)
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
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Start GhostEdit automatically when you log in",
        target: nil,
        action: nil
    )
    private let hintLabel = NSTextField(labelWithString: "")

    private let providerOptions: [CLIProvider] = [.claude, .codex, .gemini]
    private var modelOptions: [ModelOption] = []

    init(configManager: ConfigManager, onConfigSaved: @escaping (AppConfig) -> Void) {
        self.configManager = configManager
        self.onConfigSaved = onConfigSaved

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostEdit Settings"
        window.isReleasedWhenClosed = false
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

        let rootStack = NSStackView()
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

        let subtitle = NSTextField(labelWithString: "Choose provider and model used for correction.")
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

        launchAtLoginCheckbox.setContentHuggingPriority(.required, for: .vertical)
        rootStack.addArrangedSubview(launchAtLoginCheckbox)

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
        switch provider {
        case .claude:
            return [
                ModelOption(title: "Claude default (haiku)", value: "haiku"),
                ModelOption(title: "Sonnet", value: "sonnet"),
                ModelOption(title: "Opus", value: "opus"),
                ModelOption(title: "Custom", value: nil)
            ]
        case .codex:
            return [
                ModelOption(title: "Codex provider default", value: ""),
                ModelOption(title: "gpt-5.3-codex", value: "gpt-5.3-codex"),
                ModelOption(title: "gpt-5-codex", value: "gpt-5-codex"),
                ModelOption(title: "Custom", value: nil)
            ]
        case .gemini:
            return [
                ModelOption(title: "Gemini provider default", value: ""),
                ModelOption(title: "gemini-2.5-flash", value: "gemini-2.5-flash"),
                ModelOption(title: "gemini-2.5-pro", value: "gemini-2.5-pro"),
                ModelOption(title: "Custom", value: nil)
            ]
        }
    }

    private func updateHint(for provider: CLIProvider) {
        hintLabel.stringValue = "If a \(provider.displayName) model is busy or fails, switch to another model here and try again."
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
        if selectedOptionValue() == nil, model.isEmpty {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Model is required"
            alert.informativeText = "Choose a model or enter a custom model name."
            alert.runModal()
            return
        }

        var config = configManager.loadConfig()
        config.provider = provider.rawValue
        config.model = model
        config.launchAtLogin = (launchAtLoginCheckbox.state == .on)

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
