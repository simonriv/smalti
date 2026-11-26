import AppKit
import SmaltiCore

/// Primary adapter for ⌘?: shows `HelpCatalog` for the keymap in effect, filters as the user types, moves with ↑↓,
/// runs the selected row's command with ↩ and closes with esc or a click outside. Decisions are the domain's.
@MainActor
final class HelpController: NSObject, NSTextFieldDelegate {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private let keymap: () -> Keymap
    private let perform: (CommandID) -> Void
    private var view: HelpView?
    private var theme = Theme.obsidian
    private var entries: [HelpEntry] = []
    private var selected = 0
    private var outsideClicks: Any?

    init(window: SmaltiWindow, keymap: @escaping () -> Keymap, perform: @escaping (CommandID) -> Void) {
        self.window = window
        self.keymap = keymap
        self.perform = perform
    }

    func toggle(theme: Theme) {
        isOpen ? close() : open(theme: theme)
    }

    func open(theme: Theme) {
        guard !isOpen, let content = window.contentView else { return }
        self.theme = theme
        let view = HelpView(theme: theme)
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.help.width),
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.help.topOffset),
        ])
        view.field.delegate = self
        view.onClickEntry = { [weak self] index in self?.run(index) }
        self.view = view
        isOpen = true
        refresh()
        window.makeFirstResponder(view.field)
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        view?.removeFromSuperview()
        view = nil
        isOpen = false
        outsideClicks.map(NSEvent.removeMonitor)
        outsideClicks = nil
        onOpenChange?(false)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        selected = 0
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertNewline(_:)): run(selected)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    // MARK: - Rows

    private func refresh() {
        guard let view else { return }
        let sections = HelpCatalog.filtered(
            HelpCatalog.sections(keymap: keymap(), texts: .spanish) /* T9 */, query: view.field.stringValue)
        entries = Self.readingOrder(sections)
        selected = min(selected, max(entries.count - 1, 0))
        view.show(
            sections, selected: selected, maximumListHeight: maximumListHeight,
            showsCommandNames: !view.field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The entries in the order the view numbers them: left column, then right (`HelpView` balances by rows).
    private static func readingOrder(_ sections: [HelpSection]) -> [HelpEntry] {
        sections.flatMap(\.entries)
    }

    private func move(by step: Int) {
        guard !entries.isEmpty else { return }
        selected = (selected + step + entries.count) % entries.count
        view?.highlight(selected)
    }

    /// Closes first so the keyboard returns to the terminal, then runs the row's command; rows without one (Tab,
    /// ⌘clic) only close nothing.
    private func run(_ index: Int) {
        guard entries.indices.contains(index), let command = entries[index].command else { return }
        close()
        perform(command)
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard event.window === window, let view else { return }
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { close() }
    }

    private var maximumListHeight: Double {
        guard let content = window.contentView else { return 0 }
        let fixed = theme.palette.fieldHeight + theme.palette.footerHeight
        let available = min(theme.help.maximumHeight, content.bounds.height - 2 * theme.help.topOffset)
        return max(0, available - fixed)
    }
}
