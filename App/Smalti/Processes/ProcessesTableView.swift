import AppKit
import SmaltiCore

/// The processes or ports table: the observatory's 34 pt header and the mockup's 36 pt rows on the view's column
/// template, virtualized by NSTableView (hundreds of processes). The chosen row gets the accent glow and a 2 pt bar.
@MainActor
final class ProcessesTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let theme: Theme
    private let table = KeylessProcessesTable()
    private let scroll = NSScrollView()
    private let header: ProcessesRowView
    private let empty: NSTextField
    private var screen: ProcessesScreen?
    private var rows: [ProcessesRowModel] = []
    private var selected: String?
    var onSelect: ((String) -> Void)?

    private static let rowIdentifier = NSUserInterfaceItemIdentifier("processes.row")

    init(theme: Theme) {
        self.theme = theme
        header = ProcessesRowView(theme: theme, isHeader: true)
        empty = ObservatoryText.label(
            "", .init(size: theme.observatory.rowFontSize, color: theme.text.secondary), theme: theme)
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        // `.automatic` resolves to `.inset`, whose side padding would shift rows away from the header's columns.
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.rowHeight = theme.processes.rowHeight
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityIdentifier("smalti.processes.table")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        empty.setAccessibilityIdentifier("smalti.processes.empty")
        for view in [header, scroll, empty] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: theme.observatory.tableHeaderHeight),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.topAnchor.constraint(equalTo: header.bottomAnchor, constant: theme.observatory.cardPaddingVertical),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.observatory.cellPadding),
            empty.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -theme.observatory.cellPadding),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Reloads only what changed and scrolls only when the selection moves, so the 2 s refresh never pulls the list
    /// back while the person scrolls through it.
    func show(_ screen: ProcessesScreen) {
        let selectionMoved = screen.selected != selected
        header.columns = screen.columns
        header.showHeader(screen.headers)
        if screen.rows != rows || selectionMoved || screen.columns != self.screen?.columns {
            self.screen = screen
            rows = screen.rows
            selected = screen.selected
            table.reloadData()
        }
        empty.stringValue = screen.empty ?? ""
        empty.isHidden = screen.empty == nil
        if selectionMoved, let index = rows.firstIndex(where: { $0.id == selected }) { table.scrollRowToVisible(index) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view =
            tableView.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? ProcessesRowView
            ?? ProcessesRowView(theme: theme, isHeader: false)
        view.identifier = Self.rowIdentifier
        view.columns = screen?.columns ?? []
        view.show(rows[row], isSelected: rows[row].id == selected, isFirst: row == 0)
        return view
    }

    /// A click selects through the controller, after this callback returns (a reload inside it would re-enter).
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let id = rows[row].id
        DispatchQueue.main.async { [weak self] in self?.onSelect?(id) }
        return false
    }
}

/// The table never takes the keyboard: ↑↓, ↵, esc and the filter stay with the view after a click on a row.
@MainActor
private final class KeylessProcessesTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

/// One line of the table (or its header), laid out on the column template.
@MainActor
final class ProcessesRowView: NSView {
    private let theme: Theme
    private let isHeader: Bool
    private var cells: [NSView] = []
    private var isSelected = false
    private var isFirst = true
    private var shownHeaders: [String] = []
    var columns: [Double?] = []

    init(theme: Theme, isHeader: Bool) {
        self.theme = theme
        self.isHeader = isHeader
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func showHeader(_ titles: [String]) {
        guard titles != shownHeaders else { return }
        shownHeaders = titles
        replace(titles.map { ObservatoryText.caption($0, theme: theme) })
    }

    func show(_ row: ProcessesRowModel, isSelected: Bool, isFirst: Bool) {
        self.isSelected = isSelected
        self.isFirst = isFirst
        replace(row.cells.map(cell))
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityIdentifier(row.accessibilityIdentifier)
        setAccessibilityLabel(row.accessibilityLabel)
        setAccessibilityValue(isSelected ? "selected" : "")
        needsDisplay = true
    }

    private var fontSize: Double { theme.observatory.rowFontSize }

    private func cell(_ content: ProcessesCell) -> NSView {
        switch content {
        case .state(let state): stateCell(state)
        case .process(let process): processCell(process)
        case .text(let text, let style): textCell(text, style)
        case .cpu(let value): cpuCell(value)
        }
    }

    private func textCell(_ text: String, _ style: ProcessesTextStyle) -> NSView {
        switch style {
        case .title: ObservatoryText.label(text, .init(size: fontSize, color: theme.text.title), theme: theme)
        case .primary: ObservatoryText.label(text, .init(size: fontSize, color: theme.header.directory), theme: theme)
        case .secondary: ObservatoryText.label(text, .init(size: fontSize, color: theme.text.secondary), theme: theme)
        case .mono:
            ObservatoryText.number(
                text, .init(size: theme.processes.commandFontSize, color: theme.header.directory), theme: theme)
        case .monoSecondary:
            ObservatoryText.number(text, .init(size: fontSize, color: theme.text.secondary), theme: theme)
        case .monoTitle: ObservatoryText.number(text, .init(size: fontSize, color: theme.text.title), theme: theme)
        }
    }

    private func stateCell(_ state: ProcessState) -> NSView {
        let dot = StatusDot(diameter: theme.observatory.tableDot, style: theme.statusDot(for: state))
        let text = ObservatoryText.label(
            ProcessFormat.state(state, texts: .current),
            .init(size: fontSize, color: theme.stateTextColor(for: state)), theme: theme)
        let stack = NSStackView(views: [dot, text])
        stack.spacing = theme.observatory.spacing.stateDot
        return stack
    }

    /// Dot, tree guides, name, command, tag and hint, each with the mockup's gap after it.
    private func processCell(_ content: ProcessCellContent) -> NSView {
        let tokens = theme.processes
        let stack = NSStackView()
        stack.spacing = 0
        let add = { (view: NSView, gap: Double) in
            stack.addArrangedSubview(view)
            stack.setCustomSpacing(gap, after: view)
        }
        if let dot = content.dot {
            add(
                StatusDot(diameter: theme.observatory.tableDot, style: theme.statusDot(for: dot)),
                theme.observatory.spacing.stateDot)
        }
        if !content.prefix.isEmpty {
            add(ObservatoryText.number(content.prefix, .init(size: fontSize, color: tokens.treeGuide), theme: theme), 0)
        }
        let nameColor = content.isContext ? tokens.contextText : theme.text.title
        add(
            ObservatoryText.label(
                content.name, .init(size: fontSize, color: nameColor, weight: theme.observatory.pillWeight),
                theme: theme), tokens.commandGap)
        let detail = ObservatoryText.number(
            content.detail, .init(size: tokens.commandFontSize, color: theme.text.secondary), theme: theme)
        // Above `fittingSize`'s level (50), so the command shows and only truncates.
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        add(detail, tokens.tagGap)
        if let tag = content.tag { add(ProtectedTag(tag, theme: theme), tokens.commandGap) }
        if let hint = content.hint {
            add(
                ObservatoryText.label(
                    hint, .init(size: tokens.commandFontSize, color: theme.agent.waiting), theme: theme), 0)
        }
        return stack
    }

    private func cpuCell(_ value: Double?) -> NSView {
        let tokens = theme.processes
        let bar = ContextBar()
        // The bar fills at 50 %: most processes use a sliver of one core.
        bar.show(fraction: min((value ?? 0) / 50, 1), fill: theme.accent, track: theme.header.contextBarTrack)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: tokens.cpuBarWidth),
            bar.heightAnchor.constraint(equalToConstant: theme.header.contextBarHeight),
        ])
        let isQuiet = (value ?? 0) < ProcessState.activeThreshold
        let text = ObservatoryText.number(
            ProcessFormat.cpu(value),
            .init(size: fontSize, color: isQuiet ? theme.text.secondary : theme.text.primary), theme: theme)
        let stack = NSStackView(views: [bar, text])
        stack.spacing = tokens.cpuBarGap
        return stack
    }

    private func replace(_ views: [NSView]) {
        cells.forEach { $0.removeFromSuperview() }
        cells = views
        views.forEach(addSubview)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let padding = theme.observatory.cellPadding
        let fixed = columns.compactMap { $0 }.reduce(0, +)
        let flexibleCount = Double(columns.filter { $0 == nil }.count)
        let flexible = max(0, bounds.width - fixed) / max(flexibleCount, 1)
        var x = 0.0
        for (cell, width) in zip(cells, columns.map { $0 ?? flexible }) {
            let size = cell.fittingSize
            let room = width - padding
            cell.frame = NSRect(
                x: x + padding, y: (bounds.height - size.height) / 2, width: min(size.width, room),
                height: size.height)
            x += width
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = theme.observatory
        let hairline = theme.chrome.hairlineWidth
        if isHeader {
            tokens.cardBorder.nsColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: hairline).fill()
            return
        }
        if isSelected {
            theme.focus.glow.nsColor.setFill()
            bounds.fill()
            theme.accent.nsColor.setFill()
            NSRect(x: 0, y: 0, width: tokens.spacing.selectionBar, height: bounds.height).fill()
        }
        if !isFirst {
            tokens.rowBorder.nsColor.setFill()
            NSRect(x: 0, y: bounds.height - hairline, width: bounds.width, height: hairline).fill()
        }
    }
}

/// "protegido": a thin-bordered tag after the command.
@MainActor
private final class ProtectedTag: NSView {
    init(_ text: String, theme: Theme) {
        super.init(frame: .zero)
        let tokens = theme.processes
        wantsLayer = true
        layer?.cornerRadius = tokens.tagRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = tokens.tagBorder.nsColor.cgColor
        let label = ObservatoryText.label(
            text, .init(size: tokens.tagFontSize, color: theme.text.secondary), theme: theme)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.tagPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.tagPadding),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
