import AppKit
import OSLog
import SmaltiCore

/// Primary adapter for ⌘K: shows the ranked commands for the typed query, moves the selection with ↑↓, runs the
/// selected command with ↵ and closes with esc. "Renombrar workspace…" turns the same field into a name prompt.
/// Ranking and availability come from the domain (`SearchCommands`); this type only displays and dispatches.
@MainActor
final class CommandPaletteController: NSObject, NSTextFieldDelegate {
    /// What the palette reads from and sends to the rest of the app.
    struct Actions {
        let search: (String) -> [RankedCommand]
        let perform: (CommandID) -> Void
        let rename: (String) -> Void
        let currentWorkspaceName: () -> String
    }

    private enum Mode {
        case searching
        case renaming
    }

    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private let actions: Actions
    private var view: CommandPaletteView?
    /// The theme the open palette was built with.
    private var theme = Theme.obsidian
    /// All results in screen order (sections flattened); the table builds only the rows in view.
    private var results: [RankedCommand] = []
    /// The list's rows: a group label wherever the group changes, then its commands (indices into `results`).
    private var items: [PaletteItem] = []
    /// The selected result; ↑↓ wrap at the ends.
    private var selection = 0
    /// A group label's height in this theme, measured once per opening rather than per keystroke.
    private var groupLabelHeight = 0.0
    private var mode = Mode.searching
    private let signposter = OSSignposter(subsystem: AppIdentity.current.bundleIdentifier, category: "palette")
    private var outsideClicks: Any?
    private var resizes: NSObjectProtocol?

    init(window: SmaltiWindow, actions: Actions) {
        self.window = window
        self.actions = actions
    }

    func toggle(theme: Theme) {
        isOpen ? close() : open(theme: theme)
    }

    /// B7: the palette must open in 50 ms or less; the "palette.open" interval spans building, the first layout and
    /// the first display.
    func open(theme: Theme) {
        guard !isOpen else { return }
        let interval = signposter.beginInterval("palette.open")
        present(theme: theme, mode: .searching)
        refresh()
        view?.layoutSubtreeIfNeeded()
        view?.displayIfNeeded()
        signposter.endInterval("palette.open", interval)
    }

    func close() {
        guard isOpen else { return }
        // The field editor's undo stack is the window's; a later palette must not undo this one's typing.
        window.undoManager?.removeAllActions()
        view?.removeFromSuperview()
        view = nil
        items = []
        isOpen = false
        stopObserving()
        onOpenChange?(false)
    }

    /// "Renombrar workspace…": the field shows the current name, selected, and ↵ applies it.
    func beginRename(theme: Theme) {
        if !isOpen { present(theme: theme, mode: .renaming) }
        guard let view else { return }
        mode = .renaming
        items = []
        view.show(.empty, maximumListHeight: 0)
        view.showNavigationHint(false)
        view.field.stringValue = actions.currentWorkspaceName()
        view.field.currentEditor()?.selectAll(nil)
    }

    private func present(theme: Theme, mode: Mode) {
        self.theme = theme
        groupLabelHeight = CommandGroupLabel(.tiling, theme: theme).fittingSize.height
        let view = CommandPaletteView(theme: theme)
        place(view, theme: theme)
        view.field.delegate = self
        self.view = view
        self.mode = mode
        isOpen = true
        window.makeFirstResponder(view.field)
        startObserving()
        onOpenChange?(true)
    }

    // MARK: - Window events while open

    /// A click outside the palette closes it (and still reaches what was clicked); a resize refits the list.
    private func startObserving() {
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        resizes = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refitList() }
        }
    }

    private func stopObserving() {
        outsideClicks.map(NSEvent.removeMonitor)
        outsideClicks = nil
        resizes.map(NotificationCenter.default.removeObserver)
        resizes = nil
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard event.window === window, let view else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        if !view.bounds.contains(point) { close() }
    }

    private func refitList() {
        guard mode == .searching else { return }
        view?.fitList(maximumHeight: maximumListHeight)
        // A shorter list (macOS tiling halves the window with the palette open) can clip the selection again.
        revealSelection()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard mode == .searching else { return }
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)): commit()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    // MARK: - Results

    /// Results follow the domain's sections, so the selection order is the order on screen.
    private func refresh() {
        guard let view else { return }
        results = CommandSection.grouping(actions.search(view.field.stringValue)).flatMap(\.commands)
        items = PaletteItem.items(for: results)
        selection = 0
        view.show(listContent(), maximumListHeight: maximumListHeight)
        revealSelection()
    }

    /// The commands on offer changed while the palette is open (F5.6: the Claude integration's state): the list is
    /// rebuilt for the same query, keeping the selected command when it is still there.
    func catalogChanged() {
        guard isOpen, mode == .searching, let view else { return }
        let selected = results.indices.contains(selection) ? results[selection].command.id : nil
        results = CommandSection.grouping(actions.search(view.field.stringValue)).flatMap(\.commands)
        items = PaletteItem.items(for: results)
        selection = results.firstIndex { $0.command.id == selected } ?? 0
        view.show(listContent(), maximumListHeight: maximumListHeight)
        revealSelection()
    }

    private func listContent() -> PaletteListContent {
        let rowHeight = theme.palette.rowHeight
        let labelHeight = groupLabelHeight
        return PaletteListContent(
            count: items.count,
            height: { [items] in
                if case .group = items[$0] { return labelHeight }
                return rowHeight
            },
            view: { [weak self] in self?.makeView(at: $0) ?? NSView() })
    }

    private func makeView(at index: Int) -> NSView {
        switch items[index] {
        case .group(let group): return CommandGroupLabel(group, theme: theme)
        case .command(let result):
            let ranked = results[result]
            let row = CommandRowView(ranked.command, theme: theme)
            row.onClick = { [weak self] in self?.run(ranked.command.id) }
            row.setSelected(result == selection)
            return row
        }
    }

    private func moveSelection(by step: Int) {
        guard !results.isEmpty, mode == .searching else { return }
        let previous = selection
        selection = ((selection + step) % results.count + results.count) % results.count
        setSelected(previous, false)
        setSelected(selection, true)
        revealSelection()
    }

    private func setSelected(_ result: Int, _ isSelected: Bool) {
        guard let index = itemIndex(of: result) else { return }
        (view?.builtView(at: index)?.subviews.first as? CommandRowView)?.setSelected(isSelected)
    }

    private func itemIndex(of result: Int) -> Int? {
        items.firstIndex { if case .command(result) = $0 { true } else { false } }
    }

    /// The selected row with its group label when it opens a group.
    private func revealSelection() {
        guard let index = itemIndex(of: selection) else { return }
        let label: Int? = index > 0 && items[index - 1].isGroup ? index - 1 : nil
        view?.reveal(index, label: label)
    }

    private func commit() {
        switch mode {
        case .renaming:
            let name = view?.field.stringValue ?? ""
            close()
            actions.rename(name)
        case .searching:
            guard results.indices.contains(selection) else { return }
            run(results[selection].command.id)
        }
    }

    /// Closes first so the keyboard returns to the terminal, then runs the command.
    private func run(_ command: CommandID) {
        close()
        actions.perform(command)
    }

    // MARK: - Placement

    /// Centred, `topOffset` below the top of the window, above everything else in the window content.
    private func place(_ view: CommandPaletteView, theme: Theme) {
        guard let content = window.contentView else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.palette.width),
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.palette.topOffset),
        ])
    }

    /// The list never pushes the palette past a margin as large as its top offset.
    private var maximumListHeight: Double {
        guard let content = window.contentView else { return 0 }
        let fixed = theme.palette.fieldHeight + theme.palette.footerHeight
        return max(0, content.bounds.height - 2 * theme.palette.topOffset - fixed)
    }
}

/// A row of the palette list: a group label or a result.
enum PaletteItem: Equatable {
    case group(CommandGroup)
    case command(Int)

    var isGroup: Bool {
        if case .group = self { true } else { false }
    }

    /// A group label wherever the group changes, then the results of that group.
    static func items(for results: [RankedCommand]) -> [PaletteItem] {
        var items: [PaletteItem] = []
        var previous: CommandGroup?
        for (index, ranked) in results.enumerated() {
            if ranked.command.group != previous { items.append(.group(ranked.command.group)) }
            previous = ranked.command.group
            items.append(.command(index))
        }
        return items
    }
}
