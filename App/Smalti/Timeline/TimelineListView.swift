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
        // The one column fills the list, so a chosen row's glow spans it whole.
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
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
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: theme.timeline.listTop),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private var shownBody: TimelineScreen.Body?

    func show(_ screen: TimelineScreen) {
        let previous = selected
        selected = screen.selected
        // Only the choice moved: repaint those two rows, not the whole list (review 2, I5).
        if screen.body == shownBody {
            let rows = [previous, screen.selected].compactMap { tableRow(of: $0) }
            table.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: IndexSet(integer: 0))
            if let row = tableRow(of: screen.selected) { table.scrollRowToVisible(row) }
            return
        }
        shownBody = screen.body
        entries = Self.entries(screen.body)
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
        case .hit(_, _, _, _, let item):
            // Hits are chosen by their place among the hits, as ↑↓ count them.
            let hits = entries.compactMap { if case .hit(_, _, _, _, let at) = $0 { at } else { nil } }
            if let position = hits.firstIndex(of: item) { onChoose?(position) }
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

    /// Heights from each row's content, without building its view: automatic heights made the table build every
    /// row's view to size the list (1.4 GB with a 60 MB session; spec C8). Only the visible rows exist.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let tokens = theme.timeline
        let line = tokens.textFontSize * 1.45
        let mono = tokens.monoFontSize * 1.55
        let perLine = max(
            20,
            Int(
                (tokens.width - tokens.itemPaddingLeading - tokens.padding - tokens.textWidthInset)
                    / (tokens.textFontSize * 0.55)))
        func lines(_ text: String, clamp: Int) -> Int {
            let explicit = text.split(separator: "\n", omittingEmptySubsequences: false)
            let wrapped = explicit.reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
            return min(clamp, max(1, wrapped))
        }
        switch entries[row] {
        case .row(let item, _):
            switch item.kind {
            case .prompt, .reply:
                let clamp = item.kind == .prompt ? tokens.promptLines : tokens.replyLines
                return 2 * tokens.itemPaddingVertical + tokens.whoFontSize * 1.5 + tokens.textGap
                    + Double(lines(item.text, clamp: clamp)) * line
            case .tool:
                guard item.isExpanded, let output = item.expandedText else { return tokens.toolRowHeight }
                let shown = output.split(separator: "\n", omittingEmptySubsequences: false).count
                let more = item.moreLines > 0 ? tokens.smallFontSize * 1.5 : 0
                return tokens.toolRowHeight + 2 * tokens.outputPaddingVertical + tokens.outputBottom + tokens.outputGap
                    * 2
                    + tokens.whoFontSize * 1.5 + Double(shown) * mono + more + tokens.outputGap
            case .image, .compaction: return 2 * tokens.notePaddingVertical + tokens.smallFontSize * 1.5
            }
        case .group:
            return tokens.groupPaddingTop + tokens.groupPaddingBottom + tokens.groupGap + 2 * tokens.groupTitleSize
                * 1.4
        case .hit(_, _, let snippet, _, _):
            return 2 * tokens.hitPaddingVertical + tokens.whoFontSize * 1.5 + tokens.hitGap
                + Double(lines(snippet, clamp: tokens.hitLines)) * tokens.hitFontSize * 1.45
        case .message(let title, let body):
            return tokens.emptyPaddingTop + tokens.emptyPaddingBottom + tokens.emptyDotSize + 2 * tokens.emptyGap
                + Double(lines(title, clamp: tokens.emptyTitleLines)) * tokens.emptyTitleSize * 1.4
                + Double(lines(body, clamp: tokens.emptyBodyLines)) * tokens.emptyBodySize * 1.5
        case .caption: return tokens.captionPaddingTop + tokens.captionPaddingBottom + tokens.whoFontSize * 1.5
        case .recent: return tokens.recentRowHeight
        }
    }
}
