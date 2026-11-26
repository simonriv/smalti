import AppKit
import SmaltiCore

/// The timeline's list: a view-based `NSTableView` with automatic row heights, so only the visible rows exist (a
/// session of thousands of items costs only what is on screen). It lists the session's rows, the search's groups
/// and hits, or the empty state with the recent sessions.
@MainActor
final class TimelineListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private enum Entry {
        case row(TimelineRow, index: Int)
        case group(title: String, meta: String, count: Int)
        case hit(who: String, time: String, snippet: String, match: NSRange, index: Int)
        case message(title: String, body: String)
        case caption(String)
        case recent(TimelineScreen.Recent, index: Int)
    }

    private let theme: Theme
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var entries: [Entry] = []
    private var selected: Int?
    var onChoose: ((Int) -> Void)?

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.usesAutomaticRowHeights = true
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.refusesFirstResponder = true
        table.target = self
        table.action = #selector(clicked)
        table.setAccessibilityIdentifier("smalti.timeline.list")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ screen: TimelineScreen) {
        entries = Self.entries(screen.body)
        selected = screen.selected
        table.reloadData()
        if let row = tableRow(of: screen.selected) { table.scrollRowToVisible(row) }
    }

    private static func entries(_ body: TimelineScreen.Body) -> [Entry] {
        switch body {
        case .loading(let text): [.caption(text)]
        case .failed(let text): [.message(title: text, body: "")]
        case .session(_, _, let rows): rows.enumerated().map { .row($1, index: $0) }
        case .empty(let title, let body, let recentTitle, let recent):
            [.message(title: title, body: body), .caption(recentTitle)]
                + recent.enumerated().map { .recent($1, index: $0) }
        case .search(_, _, _, _, let items):
            items.enumerated().map { index, item in
                switch item {
                case .group(let title, let meta, let count): .group(title: title, meta: meta, count: count)
                case .hit(let who, let time, let snippet, let match):
                    .hit(who: who, time: time, snippet: snippet, match: match, index: index)
                }
            }
        }
    }

    /// The table row showing the body's item `index` (rows, hits by their item index, recent sessions).
    private func tableRow(of index: Int?) -> Int? {
        guard let index else { return nil }
        return entries.firstIndex { entry in
            switch entry {
            case .row(_, let at), .recent(_, let at), .hit(_, _, _, _, let at): at == index
            default: false
            }
        }
    }

    @objc private func clicked() {
        guard entries.indices.contains(table.clickedRow) else { return }
        switch entries[table.clickedRow] {
        case .row(_, let index), .recent(_, let index): onChoose?(index)
        default: break
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cells = TimelineCells(theme: theme)
        switch entries[row] {
        case .row(let item, let index): return cells.row(item, index: index, isSelected: index == selected)
        case .group(let title, let meta, let count): return cells.group(title: title, meta: meta, count: count)
        case .hit(let who, let time, let snippet, let match, let index):
            return cells.hit(
                who: who, time: time, snippet: snippet, match: match, isSelected: index == selected, number: row)
        case .message(let title, let body): return cells.message(title: title, body: body)
        case .caption(let text): return cells.caption(text)
        case .recent(let recent, let index): return cells.recent(recent, isSelected: index == selected, number: index)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
