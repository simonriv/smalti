import AppKit
import SmaltiCore

/// The sessions table: a 34 pt header and 44 pt rows on the board's column template, virtualized by NSTableView
/// (30 days can be hundreds of rows). The selected row gets the accent glow and a 2 pt inner bar.
@MainActor
final class SessionTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let theme: Theme
    private let table = KeylessTable()
    private let scroll = NSScrollView()
    private var rows: [ObservatoryReport.Row] = []
    private var selectedID: String?
    var onSelect: ((String) -> Void)?

    private static let headers = [
        String(localized: "State"), String(localized: "Session"), String(localized: "Agent · model"),
        String(localized: "Age"), String(localized: "Input"), String(localized: "Output"), String(localized: "Context"),
        "Err", "PID",
    ]
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("observatory.row")

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let header = TableRowView(theme: theme, isHeader: true)
        header.showHeader(Self.headers)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        // `.automatic` resolves to `.inset`, whose side padding would shift rows away from the header's columns.
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.rowHeight = theme.observatory.rowHeight
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityIdentifier("smalti.observatory.table")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: theme.observatory.tableHeaderHeight),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Reloads only what changed, and scrolls only when the selection moves, so a refresh every 2 s never pulls
    /// the list back while the user scrolls through it.
    func show(_ rows: [ObservatoryReport.Row], selected: String?) {
        let selectionMoved = selected != selectedID
        if rows != self.rows || selectionMoved {
            self.rows = rows
            selectedID = selected
            table.reloadData()
        }
        if selectionMoved, let index = rows.firstIndex(where: { $0.id == selected }) { table.scrollRowToVisible(index) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view =
            tableView.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? TableRowView
            ?? TableRowView(theme: theme, isHeader: false)
        view.identifier = Self.rowIdentifier
        view.show(rows[row], isSelected: rows[row].id == selectedID, isFirst: row == 0)
        return view
    }

    /// A click selects through the controller, after this callback returns (a reload inside it would re-enter).
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let id = rows[row].id
        DispatchQueue.main.async { [weak self] in self?.onSelect?(id) }
        return false
    }
}

/// The table never takes the keyboard: ↑↓, ↵ and esc stay with the observatory after a click on a row.
@MainActor
private final class KeylessTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

/// One line of the table (or its header), laid out on the column template.
@MainActor
private final class TableRowView: NSView {
    private let theme: Theme
    private let isHeader: Bool
    private var cells: [NSView] = []
    private var isSelected = false
    private var isFirst = true

    init(theme: Theme, isHeader: Bool) {
        self.theme = theme
        self.isHeader = isHeader
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func showHeader(_ titles: [String]) {
        replace(titles.map { ObservatoryText.caption($0, theme: theme) })
    }

    func show(_ row: ObservatoryReport.Row, isSelected: Bool, isFirst: Bool) {
        self.isSelected = isSelected
        self.isFirst = isFirst
        let tokens = theme.observatory
        let stopped = row.state == .stopped
        let primary = stopped ? theme.text.secondary : theme.text.title
        let muted = stopped ? theme.text.secondary : theme.header.directory
        let number = { (text: String, color: RGBAColor) in
            ObservatoryText.number(text, .init(size: tokens.rowFontSize, color: color), theme: self.theme)
        }
        replace([
            stateCell(row.state),
            ObservatoryText.label(row.label, .init(size: tokens.rowFontSize, color: primary), theme: theme),
            ObservatoryText.label(row.agentModel, .init(size: tokens.rowFontSize, color: muted), theme: theme),
            number(row.lifetime, theme.text.primary), number(row.input, theme.text.primary),
            number(row.output, theme.text.primary), contextCell(row.context),
            number(
                ObservatoryFormat.percent(row.errorRate), row.isErrorRateHigh ? theme.agent.failed : theme.text.primary),
            number(row.pid, theme.text.secondary),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityIdentifier("smalti.observatory.row.\(row.id)")
        setAccessibilityLabel(row.label)
        setAccessibilityValue(isSelected ? "selected" : ObservatoryTexts.state(row.state, copy: .current))
        needsDisplay = true
    }

    private func stateCell(_ state: AgentStateKind) -> NSView {
        let color = state == .stopped ? theme.text.secondary : theme.color(for: state)
        let dot = StatusDot(diameter: theme.observatory.tableDot, style: theme.statusDot(for: state))
        let text = ObservatoryText.label(
            ObservatoryTexts.state(state, copy: .current),
            .init(size: theme.observatory.rowFontSize, color: color), theme: theme)
        let stack = NSStackView(views: [dot, text])
        stack.spacing = theme.observatory.spacing.stateDot
        return stack
    }

    private func contextCell(_ load: ContextLoad) -> NSView {
        guard case .percent(let value) = load else {
            return ObservatoryText.label(
                "—", .init(size: theme.observatory.rowFontSize, color: theme.text.secondary), theme: theme)
        }
        let color = load.isHigh ? theme.agent.waiting : theme.accent
        let bar = ContextBar()
        bar.show(fraction: Double(value) / 100, fill: color, track: theme.header.contextBarTrack)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: theme.observatory.contextBarWidth),
            bar.heightAnchor.constraint(equalToConstant: theme.header.contextBarHeight),
        ])
        let text = ObservatoryText.number(
            ObservatoryFormat.percent(value),
            .init(size: theme.observatory.rowFontSize, color: load.isHigh ? theme.agent.waiting : theme.text.primary),
            theme: theme)
        let stack = NSStackView(views: [bar, text])
        stack.spacing = theme.observatory.spacing.contextBar
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
        let tokens = theme.observatory
        let fixed = tokens.columns.compactMap { $0 }.reduce(0, +)
        let flexibleCount = Double(tokens.columns.filter { $0 == nil }.count)
        let flexible = max(0, bounds.width - fixed) / max(flexibleCount, 1)
        var x = 0.0
        for (cell, width) in zip(cells, tokens.columns.map { $0 ?? flexible }) {
            let size = cell.fittingSize
            // Like the board's grid cells, text may run into the trailing padding before it truncates.
            let room = width - tokens.cellPadding
            cell.frame = NSRect(
                x: x + tokens.cellPadding, y: (bounds.height - size.height) / 2, width: min(size.width, room),
                height: size.height)
            x += width
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = theme.observatory
        if isHeader {
            tokens.cardBorder.nsColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: theme.chrome.hairlineWidth).fill()
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
            NSRect(
                x: 0, y: bounds.height - theme.chrome.hairlineWidth, width: bounds.width,
                height: theme.chrome.hairlineWidth
            )
            .fill()
        }
    }
}
