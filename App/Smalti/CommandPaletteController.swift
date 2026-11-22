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
    private var rows: [CommandRowView] = []
    private var selection = 0
    private var mode = Mode.searching
    private let signposter = OSSignposter(subsystem: "dev.simonriv.smalti", category: "palette")
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
        view?.removeFromSuperview()
        view = nil
        rows = []
        isOpen = false
        stopObserving()
        onOpenChange?(false)
    }

    /// "Renombrar workspace…": the field shows the current name, selected, and ↵ applies it.
    func beginRename(theme: Theme) {
        if !isOpen { present(theme: theme, mode: .renaming) }
        guard let view else { return }
        mode = .renaming
        rows = []
        view.show([], maximumListHeight: 0)
        view.showNavigationHint(false)
        view.field.stringValue = actions.currentWorkspaceName()
        view.field.currentEditor()?.selectAll(nil)
    }

    private func present(theme: Theme, mode: Mode) {
        self.theme = theme
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

    /// Rows follow the domain's sections, so the selection order is the order on screen.
    private func refresh() {
        guard let view else { return }
        let sections = CommandSection.grouping(actions.search(view.field.stringValue))
        var views: [NSView] = []
        rows = []
        for section in sections {
            views.append(CommandGroupLabel(section.group, theme: theme))
            let sectionRows = section.commands.map(makeRow)
            rows += sectionRows
            views += sectionRows
        }
        selection = 0
        view.show(views, maximumListHeight: maximumListHeight)
        highlight()
    }

    private func makeRow(_ ranked: RankedCommand) -> CommandRowView {
        let row = CommandRowView(ranked.command, theme: theme)
        row.onClick = { [weak self] in self?.run(ranked.command.id) }
        return row
    }

    private func moveSelection(by step: Int) {
        guard !rows.isEmpty, mode == .searching else { return }
        selection = (selection + step + rows.count) % rows.count
        highlight()
    }

    private func highlight() {
        for (index, row) in rows.enumerated() { row.setSelected(index == selection) }
        if rows.indices.contains(selection) { view?.scrollToVisible(rows[selection]) }
    }

    private func commit() {
        switch mode {
        case .renaming:
            let name = view?.field.stringValue ?? ""
            close()
            actions.rename(name)
        case .searching:
            guard rows.indices.contains(selection) else { return }
            run(rows[selection].command.id)
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
