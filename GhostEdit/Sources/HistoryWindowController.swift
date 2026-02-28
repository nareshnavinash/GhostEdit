import AppKit

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
            zipped = zipped.filter { _, row in
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
