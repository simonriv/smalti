import AppKit
import SmaltiCore

/// The ⌘K panel of Paleta.dc.html: 640 pt wide, 110 pt below the top of the window, glass with a 36 pt blur,
/// a 52 pt search field, grouped rows and a 36 pt footer. It draws; `CommandPaletteController` decides.
@MainActor
final class CommandPaletteView: NSView {
    let field = PaletteField()
    private let theme: Theme
    private let table = NSTableView()
    private let source = PaletteListSource()
    private let scroll = NSScrollView()
    private var scrollHeight: NSLayoutConstraint?
    /// Under the list; hidden with it so the field and the footer never show a doubled line.
    private let listSeparator = NSView()
    private var navigateHint: NSView?

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: makeContent(), theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.palette")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// The list's rows: the table builds only the ones in view, and scrolls through all of them (F5.6). The list
    /// grows with them up to `maximumListHeight`.
    func show(_ content: PaletteListContent, maximumListHeight: Double) {
        source.content = content
        table.reloadData()
        fitList(maximumHeight: maximumListHeight)
        scroll.isHidden = content.count == 0
        listSeparator.isHidden = content.count == 0
    }

    /// The list grows with its rows up to `maximumHeight` (recomputed when the window resizes).
    func fitList(maximumHeight: Double) {
        let palette = theme.palette
        let rows = (0..<source.content.count).reduce(0) { $0 + source.content.height($1) }
        let height = source.content.count == 0 ? 0 : rows + palette.listPaddingTop + palette.listPaddingBottom
        scrollHeight?.constant = min(height, maximumHeight)
    }

    /// The row of the table at `index`, if it is built (in view).
    func builtView(at index: Int) -> NSView? {
        guard index >= 0, index < table.numberOfRows else { return nil }
        return table.view(atColumn: 0, row: index, makeIfNecessary: false)
    }

    /// Scrolls just enough to show row `index` whole, with the group label above it when `label` names one; the
    /// first rows take the list back to its top.
    func reveal(_ index: Int, label: Int?) {
        guard index >= 0, index < table.numberOfRows else { return }
        table.layoutSubtreeIfNeeded()
        if (label ?? index) == 0 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        var target = table.rect(ofRow: index)
        if let label { target = target.union(table.rect(ofRow: label)) }
        table.scrollToVisible(target)
    }

    /// The rename prompt has nothing to navigate; only "↵ ejecutar" applies.
    func showNavigationHint(_ isShown: Bool) {
        navigateHint?.isHidden = !isShown
    }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        let stack = NSStackView(views: [fieldRow(), separator(), listArea(), separator(listSeparator), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        return stack
    }

    private func fieldRow() -> NSView {
        let palette = theme.palette
        let icon = CommandIconView(CommandIcons.search, size: palette.iconSize, lineWidth: palette.searchIconStroke)
        icon.color = theme.text.secondary.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.fieldFontSize)
        field.textColor = theme.text.title.nsColor
        field.setAccessibilityLabel(String(localized: "Search commands"))
        field.setAccessibilityIdentifier("smalti.paletteField")
        let row = NSStackView(views: [icon, field, KbdView("esc", theme: theme)])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func listArea() -> NSView {
        let palette = theme.palette
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.focusRingType = .none
        table.refusesFirstResponder = true
        source.horizontalPadding = palette.listPaddingHorizontal
        table.dataSource = source
        table.delegate = source
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(
            top: palette.listPaddingTop, left: 0, bottom: palette.listPaddingBottom, right: 0)
        scroll.setAccessibilityIdentifier("smalti.palette.list")
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        scrollHeight?.isActive = true
        return scroll
    }

    /// "↑↓ navegar · ↵ ejecutar" and the board's closing line. "⌘↵ en panel nuevo" is left out: no F1 command runs
    /// in a pane (deviation justified in the PR).
    private func footer() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let navigate = hint("↑↓", String(localized: "navigate"))
        navigateHint = navigate
        let row = NSStackView(views: [
            navigate, hint("↵", String(localized: "run")), spacer,
            footerLabel(String(localized: "Everything buttons would do lives here")),
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }

    /// `<kbd>↑↓</kbd> navegar`: the board separates key and word with a plain space.
    private func hint(_ keys: String, _ action: String) -> NSView {
        OverlayBox.hint(keys, action, theme: theme)
    }

    private func footerLabel(_ text: String) -> NSTextField {
        OverlayBox.footerLabel(text, theme: theme)
    }

    private func separator(_ line: NSView = NSView()) -> NSView {
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.palette.footerBorder.nsColor.cgColor
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    private func pin(_ view: NSView, to container: NSView) {
        OverlayBox.pin(view, to: container)
    }
}

/// What the palette list shows: how many rows, how tall each one is and the view of each (built on demand).
@MainActor
struct PaletteListContent {
    static let empty = PaletteListContent(count: 0, height: { _ in 0 }, view: { _ in NSView() })

    let count: Int
    let height: (Int) -> Double
    let view: (Int) -> NSView
}

/// The table's data source and delegate: rows come from `content`, inset by the list's horizontal padding.
@MainActor
private final class PaletteListSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var content = PaletteListContent.empty
    var horizontalPadding = 0.0

    func numberOfRows(in tableView: NSTableView) -> Int { content.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { content.height(row) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = content.view(row)
        let cell = NSView()
        item.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(item)
        NSLayoutConstraint.activate([
            item.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: horizontalPadding),
            item.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -horizontalPadding),
            item.topAnchor.constraint(equalTo: cell.topAnchor),
            item.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

/// The palette's text field. Smalti has no Edit menu (the terminal owns ⌘C/⌘V), so the editing shortcuts are
/// handled here: ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z go to the field editor.
final class PaletteField: NSTextField {
    private struct Shortcut: Hashable {
        let key: String
        let isShifted: Bool
    }

    private static let editActions: [Shortcut: Selector] = [
        Shortcut(key: "a", isShifted: false): #selector(NSResponder.selectAll(_:)),
        Shortcut(key: "c", isShifted: false): #selector(NSText.copy(_:)),
        Shortcut(key: "v", isShifted: false): #selector(NSText.paste(_:)),
        Shortcut(key: "x", isShifted: false): #selector(NSText.cut(_:)),
        Shortcut(key: "z", isShifted: false): undo,
        Shortcut(key: "z", isShifted: true): redo,
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let editor = currentEditor(), flags.subtracting(.shift) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased(),
            let action = Self.editActions[Shortcut(key: key, isShifted: flags.contains(.shift))]
        else { return super.performKeyEquivalent(with: event) }
        // Undo and redo live on the window's undo manager, up the responder chain from the field editor.
        let isHistory = action == Self.undo || action == Self.redo
        return NSApp.sendAction(action, to: isHistory ? nil : editor, from: self)
    }

    private static let undo = Selector(("undo:"))
    private static let redo = Selector(("redo:"))

    /// The shared field editor does not record undo by default.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.allowsUndo = true
        return accepted
    }
}
