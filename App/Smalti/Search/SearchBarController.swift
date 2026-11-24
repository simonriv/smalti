import AppKit
import SmaltiCore

/// Primary adapter for ⌘F (F4.5): one bar at a time, on the focused pane. Typing searches the pane's scrollback in
/// libghostty; ↩/⌘G go to the next match, ⇧↩/⇧⌘G to the previous one, esc ends the search. The bar closes when its
/// pane is no longer the focused one or is gone.
@MainActor
final class SearchBarController: NSObject, NSTextFieldDelegate {
    typealias Engine = TerminalEngine & TerminalViewProvider

    var onClose: ((PaneID) -> Void)?
    private(set) var pane: PaneID?
    private let window: NSWindow
    private let engine: any Engine
    private var view: SearchBarView?
    private var progress = SearchProgress()

    var isOpen: Bool { pane != nil }

    init(window: NSWindow, engine: any Engine) {
        self.window = window
        self.engine = engine
    }

    /// Opens on `pane`, or gives the field the focus back when it is already open there.
    func open(on pane: PaneID, theme: Theme) {
        if self.pane == pane, let view {
            window.makeFirstResponder(view.field)
            return
        }
        close()
        guard let content = window.contentView, let terminal = engine.view(for: pane) else { return }
        let view = SearchBarView(theme: theme)
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        let inset = theme.panel.areaPadding
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.searchBar.width),
            view.heightAnchor.constraint(equalToConstant: theme.searchBar.height),
            view.topAnchor.constraint(equalTo: terminal.topAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: terminal.trailingAnchor, constant: -inset),
        ])
        view.field.delegate = self
        self.view = view
        self.pane = pane
        progress = SearchProgress()
        window.makeFirstResponder(view.field)
    }

    func navigate(_ direction: SearchDirection) {
        guard let pane else { return }
        engine.navigateSearch(direction, in: pane)
    }

    /// esc: ends the search in libghostty (its highlights go), removes the bar and gives the pane the keyboard back.
    func close() {
        guard let pane else { return }
        dismiss()
        onClose?(pane)
    }

    /// Ends the search and removes the bar, leaving the keyboard where it is (the focus already moved elsewhere).
    func dismiss() {
        guard let pane else { return }
        engine.endSearch(in: pane)
        view?.removeFromSuperview()
        view = nil
        self.pane = nil
    }

    /// A search event from `pane`'s terminal.
    func progress(_ event: TerminalEvent, from pane: PaneID) {
        guard pane == self.pane else { return }
        switch event {
        case .searchTotal(let count):
            let update = progress.total(count)
            progress = update.progress
            // The first match is selected once per query, as soon as there is one (`SearchProgress`).
            if update.selectsFirstMatch { engine.navigateSearch(.next, in: pane) }
        case .searchSelected(let index): progress = progress.selected(index)
        default: return
        }
        view?.showCount(progress.text)
    }

    /// Closes when the focused pane changed (a click, a workspace switch) or the pane closed.
    func follow(_ set: WorkspaceSet) {
        guard let pane, set.active.focusedPane != pane else { return }
        dismiss()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let pane, let view else { return }
        progress = progress.newQuery()
        engine.search(view.field.stringValue, in: pane)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let isShifted = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            navigate(isShifted ? .previous : .next)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }
}
