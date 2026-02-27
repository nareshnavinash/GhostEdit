import AppKit

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

    // Cloud hotkey UI controls
    private let cloudHotkeyKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cloudCommandModifierCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let cloudOptionModifierCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let cloudControlModifierCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let cloudShiftModifierCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let cloudHotkeyPreviewLabel = NSTextField(labelWithString: "")
    private let cloudHotkeyBadgeView = NSView()
    private let cloudHotkeyBadgeLabel = NSTextField(labelWithString: "")

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
    private var hfAccountStatusDot = NSTextField(labelWithString: "\u{25CF}")
    private var hfAccountStatusLabel = NSTextField(labelWithString: "Checking...")
    private var hfAccountTokenField = NSSecureTextField(string: "")
    private var hfAccountSaveBtn = NSButton(title: "Save Token", target: nil, action: nil)
    private var hfAccountLogoutBtn = NSButton(title: "Logout", target: nil, action: nil)
    private var hfAccountDetailLabel = NSTextField(labelWithString: "")

    private func buildLocalModelsTab() -> NSView {
        let config = configManager.loadConfig()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Use a flipped clip view so content starts at the top
        let flippedClip = FlippedClipView()
        flippedClip.drawsBackground = false
        scrollView.contentView = flippedClip

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

        // Section 3: Hugging Face Account
        let hfSection = buildLocalModelsHFAccountSection()
        outerStack.addArrangedSubview(hfSection)

        // Section 4: Hardware
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
        let detected = PythonEnvironmentSupport.detectPythonPath(homeDirectoryPath: home)
        if detected != "/usr/bin/python3" {
            return detected
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

        return detected
    }

    private func refreshPythonStatus() {
        let pythonPath = localModelsPythonPathField.stringValue
        let runner = localModelRunner
        Task.detached { [weak self] in
            // First check if the Python binary actually exists
            let exists = FileManager.default.fileExists(atPath: pythonPath)
            guard exists else {
                await MainActor.run {
                    self?.localModelsStatusDot.textColor = .systemRed
                    self?.localModelsStatusLabel.stringValue = "Python not found at \(pythonPath)"
                }
                return
            }

            do {
                let packages = try runner?.checkPythonPackages(pythonPath: pythonPath) ?? [:]
                let missing = packages.filter { !$0.value }.map(\.key)
                await MainActor.run { [weak self] in
                    if missing.isEmpty {
                        self?.localModelsStatusDot.textColor = .systemGreen
                        self?.localModelsStatusLabel.stringValue = "Python ready \u{2014} transformers, torch installed"
                    } else {
                        self?.localModelsStatusDot.textColor = .systemOrange
                        self?.localModelsStatusLabel.stringValue = "Missing packages: \(missing.joined(separator: ", "))"
                    }
                }
            } catch let error as LocalModelRunnerError {
                await MainActor.run { [weak self] in
                    switch error {
                    case .scriptNotFound:
                        self?.localModelsStatusDot.textColor = .systemRed
                        self?.localModelsStatusLabel.stringValue = "Inference script not found in app bundle"
                    case .processExitedWithError(let code):
                        self?.localModelsStatusDot.textColor = .systemOrange
                        self?.localModelsStatusLabel.stringValue = "Python check failed (exit \(code)) \u{2014} packages may be broken"
                    default:
                        self?.localModelsStatusDot.textColor = .systemRed
                        self?.localModelsStatusLabel.stringValue = "Python check error: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.localModelsStatusDot.textColor = .systemRed
                    self?.localModelsStatusLabel.stringValue = "Python check error: \(error.localizedDescription)"
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
        customField.isEditable = true
        customField.isSelectable = true
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

    private func buildLocalModelsHFAccountSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "HUGGING FACE ACCOUNT")
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
        cardStack.spacing = 8
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        // Status row: dot + label + logout button
        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY

        hfAccountStatusDot.font = .systemFont(ofSize: 10)
        hfAccountStatusDot.textColor = .secondaryLabelColor
        hfAccountStatusDot.setContentHuggingPriority(.required, for: .horizontal)
        statusRow.addArrangedSubview(hfAccountStatusDot)

        hfAccountStatusLabel.font = .systemFont(ofSize: 12)
        hfAccountStatusLabel.stringValue = "Checking..."
        hfAccountStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusRow.addArrangedSubview(hfAccountStatusLabel)

        hfAccountLogoutBtn.bezelStyle = .rounded
        hfAccountLogoutBtn.font = .systemFont(ofSize: 11)
        hfAccountLogoutBtn.target = self
        hfAccountLogoutBtn.action = #selector(hfLogoutClicked(_:))
        hfAccountLogoutBtn.isHidden = true
        statusRow.addArrangedSubview(hfAccountLogoutBtn)

        cardStack.addArrangedSubview(statusRow)

        // Detail label (token source info)
        hfAccountDetailLabel.font = .systemFont(ofSize: 11)
        hfAccountDetailLabel.textColor = .secondaryLabelColor
        hfAccountDetailLabel.stringValue = ""
        cardStack.addArrangedSubview(hfAccountDetailLabel)

        // Token input row
        let tokenRow = NSStackView()
        tokenRow.orientation = .horizontal
        tokenRow.spacing = 8
        tokenRow.alignment = .centerY

        let tokenLabel = NSTextField(labelWithString: "Token:")
        tokenLabel.font = .systemFont(ofSize: 11)
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenRow.addArrangedSubview(tokenLabel)

        hfAccountTokenField.placeholderString = "hf_..."
        hfAccountTokenField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hfAccountTokenField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hfAccountTokenField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        tokenRow.addArrangedSubview(hfAccountTokenField)

        hfAccountSaveBtn.bezelStyle = .rounded
        hfAccountSaveBtn.font = .systemFont(ofSize: 11)
        hfAccountSaveBtn.target = self
        hfAccountSaveBtn.action = #selector(hfSaveTokenClicked(_:))
        tokenRow.addArrangedSubview(hfAccountSaveBtn)

        cardStack.addArrangedSubview(tokenRow)

        // Help text
        let helpLabel = NSTextField(wrappingLabelWithString: "Get your token at huggingface.co/settings/tokens. Already logged in via huggingface-cli? Your token is auto-detected.")
        helpLabel.font = .systemFont(ofSize: 10)
        helpLabel.textColor = .tertiaryLabelColor
        cardStack.addArrangedSubview(helpLabel)

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

        // Check login status in background
        refreshHFAccountStatus()

        return container
    }

    private func refreshHFAccountStatus() {
        let config = configManager.loadConfig()
        let pythonPath = config.localModelPythonPath.isEmpty
            ? localModelsPythonPathField.stringValue : config.localModelPythonPath
        guard !pythonPath.isEmpty else {
            hfAccountStatusDot.textColor = .systemOrange
            hfAccountStatusLabel.stringValue = "Set Python path first"
            hfAccountDetailLabel.stringValue = ""
            hfAccountLogoutBtn.isHidden = true
            return
        }

        let runner = self.localModelRunner ?? LocalModelRunner()
        Task.detached {
            do {
                let result = try runner.checkHFLogin(pythonPath: pythonPath)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if result.loggedIn {
                        self.hfAccountStatusDot.textColor = .systemGreen
                        self.hfAccountStatusLabel.stringValue = "Logged in as: \(result.username)"
                        self.hfAccountLogoutBtn.isHidden = false
                        let sourceDesc = result.tokenSource == "env" ? "HF_TOKEN env var" : "~/.huggingface/token"
                        self.hfAccountDetailLabel.stringValue = "Token source: \(sourceDesc)"
                    } else {
                        self.hfAccountStatusDot.textColor = .systemRed
                        self.hfAccountStatusLabel.stringValue = "Not logged in"
                        self.hfAccountLogoutBtn.isHidden = true
                        self.hfAccountDetailLabel.stringValue = ""
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.hfAccountStatusDot.textColor = .systemOrange
                    self?.hfAccountStatusLabel.stringValue = "Could not check login"
                    self?.hfAccountDetailLabel.stringValue = ""
                    self?.hfAccountLogoutBtn.isHidden = true
                }
            }
        }
    }

    @objc private func hfSaveTokenClicked(_ sender: NSButton) {
        let token = hfAccountTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let config = configManager.loadConfig()
        let pythonPath = config.localModelPythonPath.isEmpty
            ? localModelsPythonPathField.stringValue : config.localModelPythonPath
        guard !pythonPath.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Python Path Required"
            alert.informativeText = "Please set a Python path in the Python Environment section above."
            alert.runModal()
            return
        }

        sender.isEnabled = false
        sender.title = "Saving..."
        let runner = self.localModelRunner ?? LocalModelRunner()
        Task.detached {
            do {
                let username = try runner.saveHFToken(token: token, pythonPath: pythonPath)
                await MainActor.run { [weak self] in
                    sender.isEnabled = true
                    sender.title = "Save Token"
                    self?.hfAccountTokenField.stringValue = ""
                    self?.hfAccountStatusDot.textColor = .systemGreen
                    self?.hfAccountStatusLabel.stringValue = "Logged in as: \(username)"
                    self?.hfAccountLogoutBtn.isHidden = false
                    self?.hfAccountDetailLabel.stringValue = "Token source: ~/.huggingface/token"
                }
            } catch {
                await MainActor.run {
                    sender.isEnabled = true
                    sender.title = "Save Token"
                    let alert = NSAlert()
                    alert.messageText = "Token Validation Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    @objc private func hfLogoutClicked(_ sender: NSButton) {
        let config = configManager.loadConfig()
        let pythonPath = config.localModelPythonPath.isEmpty
            ? localModelsPythonPathField.stringValue : config.localModelPythonPath

        let runner = self.localModelRunner ?? LocalModelRunner()
        Task.detached {
            try? runner.logoutHF(pythonPath: pythonPath)
            await MainActor.run { [weak self] in
                self?.hfAccountStatusDot.textColor = .systemRed
                self?.hfAccountStatusLabel.stringValue = "Not logged in"
                self?.hfAccountLogoutBtn.isHidden = true
                self?.hfAccountDetailLabel.stringValue = ""
            }
        }
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
        let recommendedRepoIDs = Set(LocalModelSupport.recommendedModels.map(\.repoID))

        for entry in merged {
            let isActive = entry.repoID == config.localModelRepoID
            let isCustom = !recommendedRepoIDs.contains(entry.repoID)
            let row = makeModelRow(
                name: entry.displayName, params: entry.parameterCount,
                disk: String(format: "%.1f GB", entry.approxDiskGB),
                status: entry.status == .ready ? "Ready" : "Not downloaded",
                isHeader: false, repoID: entry.repoID, isActive: isActive,
                isCustom: isCustom
            )
            localModelsModelRows.addArrangedSubview(row)
        }
    }

    private func makeModelRow(
        name: String, params: String, disk: String, status: String,
        isHeader: Bool, repoID: String, isActive: Bool, isCustom: Bool = false
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([nameLabel.widthAnchor.constraint(equalToConstant: 100)])

        let paramsLabel = NSTextField(labelWithString: params)
        paramsLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        paramsLabel.textColor = .secondaryLabelColor
        paramsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([paramsLabel.widthAnchor.constraint(equalToConstant: 45)])

        let diskLabel = NSTextField(labelWithString: disk)
        diskLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        diskLabel.textColor = .secondaryLabelColor
        diskLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([diskLabel.widthAnchor.constraint(equalToConstant: 50)])

        let statusLabel = NSTextField(labelWithString: status)
        statusLabel.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
        statusLabel.textColor = status == "Ready" ? .systemGreen : .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([statusLabel.widthAnchor.constraint(equalToConstant: 80)])

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

                // Custom models also get a Delete (remove) button when not downloaded
                if isCustom {
                    let removeBtn = NSButton(title: "Delete", target: self, action: #selector(deleteModelClicked(_:)))
                    removeBtn.bezelStyle = .rounded
                    removeBtn.font = .systemFont(ofSize: 10)
                    removeBtn.identifier = NSUserInterfaceItemIdentifier(repoID)
                    row.addArrangedSubview(removeBtn)
                }
            }
        }

        return row
    }

    @objc private func installPythonPackagesClicked(_ sender: NSButton) {
        let pythonPath = localModelsPythonPathField.stringValue
        let cmd = PythonEnvironmentSupport.pipInstallCommand(pythonPath: pythonPath)
        sender.isEnabled = false
        localModelsStatusLabel.stringValue = "Installing packages..."
        localModelsStatusDot.textColor = .systemGray
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            let errPipe = Pipe()
            process.standardError = errPipe
            try? process.run()
            process.waitUntilExit()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            await MainActor.run {
                sender.isEnabled = true
                if process.terminationStatus == 0 {
                    self?.localModelsStatusDot.textColor = .systemGreen
                    self?.localModelsStatusLabel.stringValue = "Packages installed successfully"
                    // Re-check status after install
                    self?.refreshPythonStatus()
                } else {
                    self?.localModelsStatusDot.textColor = .systemRed
                    // Show the last meaningful line of pip output
                    let lastLine = errStr.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .last(where: { !$0.isEmpty && !$0.hasPrefix("[notice]") }) ?? ""
                    if lastLine.isEmpty {
                        self?.localModelsStatusLabel.stringValue = "Package installation failed (exit \(process.terminationStatus))"
                    } else {
                        self?.localModelsStatusLabel.stringValue = "Install failed: \(lastLine)"
                    }
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

        let runner = self.localModelRunner ?? LocalModelRunner()
        Task.detached {
            do {
                try runner.downloadModel(
                    repoID: repoID, destPath: destPath, pythonPath: pythonPath,
                    onProgress: { line in
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? String {
                            DispatchQueue.main.async { sender.title = message }
                        }
                    }
                )
                await MainActor.run { [weak self] in
                    sender.title = "Done"
                    if let self { self.refreshModelRows(config: self.configManager.loadConfig()) }
                }
            } catch {
                await MainActor.run {
                    sender.isEnabled = true
                    sender.title = "Pull"
                    let errMsg = error.localizedDescription
                    let isGatedAccessError = errMsg.lowercased().contains("gated repo")
                        || errMsg.lowercased().contains("access to model")
                        || errMsg.contains("403")
                    let isNoTokenError = errMsg.contains("401")
                        || errMsg.lowercased().contains("authorization")
                    let alert = NSAlert()
                    if isGatedAccessError {
                        alert.messageText = "Model Access Required"
                        alert.informativeText = "This model is gated and requires you to accept the license on HuggingFace.\n\n1. Visit the model page (link in the error below)\n2. Click \"Agree and access repository\"\n3. Wait for approval, then try Pull again\n\n\(errMsg)"
                    } else if isNoTokenError {
                        alert.messageText = "Authentication Required"
                        alert.informativeText = "This model requires HuggingFace authentication. Please add your token in the Hugging Face Account section below.\n\nOriginal error: \(errMsg)"
                    } else {
                        alert.messageText = "Download Failed"
                        alert.informativeText = errMsg
                    }
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

        // Delete model files if they exist
        let modelDir = LocalModelSupport.modelDirectoryURL(
            baseDirectoryURL: configManager.baseDirectoryURL, repoID: repoID
        )
        try? FileManager.default.removeItem(at: modelDir)

        var config = configManager.loadConfig()

        // Remove from custom models list if present
        if let data = config.localModelCustomModels.data(using: .utf8),
           var customModels = try? JSONDecoder().decode([LocalModelEntry].self, from: data) {
            let countBefore = customModels.count
            customModels.removeAll { $0.repoID == repoID }
            if customModels.count != countBefore {
                if let encoded = try? JSONEncoder().encode(customModels),
                   let jsonStr = String(data: encoded, encoding: .utf8) {
                    config.localModelCustomModels = jsonStr
                }
            }
        }

        // Clear active if it was selected
        if config.localModelRepoID == repoID {
            config.localModelRepoID = ""
        }
        try? configManager.saveConfig(config)
        onConfigSaved(config)
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
        let runner = localModelRunner
        Task.detached {
            do {
                let result = try runner?.correctText(
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
        let config = configManager.loadConfig()
        let hasLocalModel = !config.localModelRepoID.isEmpty

        // Dynamic hotkey labels from config
        let baseHotkey = HotkeySupport.symbolString(keyCode: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
        let shiftHotkey = HotkeySupport.symbolString(keyCode: config.cloudHotkeyKeyCode, modifiers: config.cloudHotkeyModifiers)

        // Header row
        let headerRow = makeComparisonRow(
            feature: "Feature", local: "\(baseHotkey) Local", llm: "\(shiftHotkey) LLM",
            widths: colWidths, isHeader: true
        )
        tableStack.addArrangedSubview(headerRow)

        // Data rows
        let rows: [(String, String, String)] = [
            ("Speed", hasLocalModel ? "2\u{2013}10 seconds" : "Instant", "2\u{2013}5 seconds"),
            ("Network", "None (offline)", "Requires AI CLI"),
            ("Spelling", "Yes", "Yes"),
            ("Grammar",
             hasLocalModel ? "Yes (Model + Harper)" : "Yes (Harper)",
             "Yes (contextual)"),
            ("Punctuation",
             hasLocalModel ? "Yes (Model)" : "Basic (Dictionary)",
             "Yes"),
            ("Rewrites", hasLocalModel ? "Light corrections" : "No", "Full restructuring"),
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
        // Local hotkey controls
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

        // Cloud hotkey controls
        cloudHotkeyKeyPopup.removeAllItems()
        hotkeyKeyOptions.forEach { cloudHotkeyKeyPopup.addItem(withTitle: $0.title) }
        cloudHotkeyKeyPopup.target = self
        cloudHotkeyKeyPopup.action = #selector(cloudHotkeyInputChanged)

        cloudCommandModifierCheckbox.target = self
        cloudCommandModifierCheckbox.action = #selector(cloudHotkeyInputChanged)
        cloudOptionModifierCheckbox.target = self
        cloudOptionModifierCheckbox.action = #selector(cloudHotkeyInputChanged)
        cloudControlModifierCheckbox.target = self
        cloudControlModifierCheckbox.action = #selector(cloudHotkeyInputChanged)
        cloudShiftModifierCheckbox.target = self
        cloudShiftModifierCheckbox.action = #selector(cloudHotkeyInputChanged)

        let cloudModStack = NSStackView()
        cloudModStack.orientation = .horizontal
        cloudModStack.spacing = 6
        cloudModStack.addArrangedSubview(cloudCommandModifierCheckbox)
        cloudModStack.addArrangedSubview(cloudOptionModifierCheckbox)
        cloudModStack.addArrangedSubview(cloudControlModifierCheckbox)
        cloudModStack.addArrangedSubview(cloudShiftModifierCheckbox)

        cloudHotkeyPreviewLabel.textColor = .secondaryLabelColor
        cloudHotkeyPreviewLabel.font = .systemFont(ofSize: 12, weight: .medium)

        cloudHotkeyBadgeView.wantsLayer = true
        cloudHotkeyBadgeView.layer?.cornerRadius = 6
        cloudHotkeyBadgeView.layer?.backgroundColor = NSColor.systemIndigo.withAlphaComponent(0.08).cgColor
        cloudHotkeyBadgeView.layer?.borderWidth = 1
        cloudHotkeyBadgeView.layer?.borderColor = NSColor.systemIndigo.withAlphaComponent(0.25).cgColor
        cloudHotkeyBadgeView.translatesAutoresizingMaskIntoConstraints = false

        cloudHotkeyBadgeLabel.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        cloudHotkeyBadgeLabel.textColor = .systemIndigo
        cloudHotkeyBadgeLabel.alignment = .center
        cloudHotkeyBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        cloudHotkeyBadgeView.addSubview(cloudHotkeyBadgeLabel)

        NSLayoutConstraint.activate([
            cloudHotkeyBadgeLabel.topAnchor.constraint(equalTo: cloudHotkeyBadgeView.topAnchor, constant: 8),
            cloudHotkeyBadgeLabel.bottomAnchor.constraint(equalTo: cloudHotkeyBadgeView.bottomAnchor, constant: -8),
            cloudHotkeyBadgeLabel.leadingAnchor.constraint(equalTo: cloudHotkeyBadgeView.leadingAnchor, constant: 16),
            cloudHotkeyBadgeLabel.trailingAnchor.constraint(equalTo: cloudHotkeyBadgeView.trailingAnchor, constant: -16),
        ])

        let cloudBadgeRow = NSStackView()
        cloudBadgeRow.orientation = .horizontal
        cloudBadgeRow.spacing = 8
        cloudBadgeRow.alignment = .centerY
        cloudBadgeRow.addArrangedSubview(makeFieldLabel("Current"))
        cloudBadgeRow.addArrangedSubview(cloudHotkeyBadgeView)

        let stack = makeTabStack(sections: [
            makeSection(title: "Local Hotkey", views: [
                badgeRow,
                makeRow(label: makeFieldLabel("Key"), field: hotkeyKeyPopup),
                makeRow(label: makeFieldLabel("Modifiers"), field: modStack),
                hotkeyPreviewLabel,
            ]),
            makeSection(title: "Cloud Hotkey (LLM)", views: [
                cloudBadgeRow,
                makeRow(label: makeFieldLabel("Key"), field: cloudHotkeyKeyPopup),
                makeRow(label: makeFieldLabel("Modifiers"), field: cloudModStack),
                cloudHotkeyPreviewLabel,
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
        diffPreviewDurationField.placeholderString = "5"
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
                makeRow(label: makeFieldLabel("Duration (sec)"), field: diffPreviewDurationField),
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
        loadCloudHotkeyValues(from: config)

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

    @objc private func cloudHotkeyInputChanged() {
        updateCloudHotkeyPreview()
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
            hotkeyPreviewLabel.stringValue = "Local hotkey: unavailable"
            hotkeyBadgeLabel.stringValue = "—"
            return
        }

        let modifiers = selectedHotkeyModifiers()
        let display = HotkeySupport.displayString(keyCode: keyCode, modifiers: modifiers)
        hotkeyPreviewLabel.stringValue = "Local hotkey: \(display)"
        hotkeyBadgeLabel.stringValue = display
    }

    private func loadCloudHotkeyValues(from config: AppConfig) {
        if let index = hotkeyKeyOptions.firstIndex(where: { $0.keyCode == config.cloudHotkeyKeyCode }) {
            cloudHotkeyKeyPopup.selectItem(at: index)
        } else if let defaultIndex = hotkeyKeyOptions.firstIndex(where: { $0.keyCode == HotkeySupport.defaultKeyCode }) {
            cloudHotkeyKeyPopup.selectItem(at: defaultIndex)
        } else {
            cloudHotkeyKeyPopup.selectItem(at: 0)
        }

        let split = HotkeySupport.splitModifiers(config.cloudHotkeyModifiers)
        cloudCommandModifierCheckbox.state = split.command ? .on : .off
        cloudOptionModifierCheckbox.state = split.option ? .on : .off
        cloudControlModifierCheckbox.state = split.control ? .on : .off
        cloudShiftModifierCheckbox.state = split.shift ? .on : .off

        updateCloudHotkeyPreview()
    }

    private func selectedCloudHotkeyKeyCode() -> UInt32? {
        let index = cloudHotkeyKeyPopup.indexOfSelectedItem
        guard hotkeyKeyOptions.indices.contains(index) else {
            return nil
        }
        return hotkeyKeyOptions[index].keyCode
    }

    private func selectedCloudHotkeyModifiers() -> UInt32 {
        HotkeySupport.makeModifiers(
            command: cloudCommandModifierCheckbox.state == .on,
            option: cloudOptionModifierCheckbox.state == .on,
            control: cloudControlModifierCheckbox.state == .on,
            shift: cloudShiftModifierCheckbox.state == .on
        )
    }

    private func updateCloudHotkeyPreview() {
        guard let keyCode = selectedCloudHotkeyKeyCode() else {
            cloudHotkeyPreviewLabel.stringValue = "Cloud hotkey: unavailable"
            cloudHotkeyBadgeLabel.stringValue = "—"
            return
        }

        let modifiers = selectedCloudHotkeyModifiers()
        let display = HotkeySupport.displayString(keyCode: keyCode, modifiers: modifiers)
        cloudHotkeyPreviewLabel.stringValue = "Cloud hotkey: \(display)"
        cloudHotkeyBadgeLabel.stringValue = display
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
            alert.messageText = "Local hotkey modifiers are required"
            alert.informativeText = "Select at least one modifier key (Command, Option, Control, or Shift) for the local hotkey."
            alert.runModal()
            return
        }
        guard let cloudHotkeyKeyCode = selectedCloudHotkeyKeyCode() else {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cloud hotkey key is required"
            alert.informativeText = "Choose a key for the cloud hotkey before saving."
            alert.runModal()
            return
        }
        let cloudHotkeyModifiers = selectedCloudHotkeyModifiers()
        if cloudHotkeyModifiers == 0 {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cloud hotkey modifiers are required"
            alert.informativeText = "Select at least one modifier key (Command, Option, Control, or Shift) for the cloud hotkey."
            alert.runModal()
            return
        }
        if hotkeyKeyCode == cloudHotkeyKeyCode && hotkeyModifiers == cloudHotkeyModifiers {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Hotkeys must be different"
            alert.informativeText = "The local and cloud hotkeys cannot use the same key combination."
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
        config.cloudHotkeyKeyCode = cloudHotkeyKeyCode
        config.cloudHotkeyModifiers = cloudHotkeyModifiers

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
