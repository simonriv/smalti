import AppKit
import SmaltiCore

/// Primary adapter for ⌘⇧O: the session search alone, centered on the ⌘K glass. ↑↓ move, ←→ (with the field empty)
/// and ⌘1…⌘5 change the harness, ↩ opens, ⌘↩ forks, esc and a click outside close. Decisions are the domain's.
@MainActor
final class SessionSearchController: NSObject, NSTextFieldDelegate {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private let model: SessionSearchModel
    /// Runs an open plan (a pane in the active workspace) and says what went wrong, if anything.
    private let open: (OpenPlan, _ directory: String?) -> Void
    private var view: SessionSearchView?
    private var outsideClicks: Any?

    init(window: SmaltiWindow, harnesses: HarnessRegistry, open: @escaping (OpenPlan, String?) -> Void) {
        self.window = window
        self.model = SessionSearchModel(registry: harnesses)
        self.open = open
    }

    func toggle(theme: Theme) {
        isOpen ? close() : show(theme: theme)
    }

    func show(theme: Theme) {
        guard !isOpen, let content = window.contentView else { return }
        let view = SessionSearchView(theme: theme, column: false)
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.sessionSearch.width),
            view.heightAnchor.constraint(
                equalToConstant: min(
                    theme.sessionSearch.cardHeight, content.bounds.height - 2 * theme.palette.topOffset)),
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.palette.topOffset),
        ])
        view.field.delegate = self
        view.onChip = { [weak self] index in self?.model.selectChip(index) }
        view.onClickRow = { [weak self] id in
            self?.model.select(id: id)
            self?.run(forking: false)
        }
        model.onChange = { [weak self, weak view] in
            guard let self, let view else { return }
            view.render(model.state, rows: model.rows())
        }
        self.view = view
        isOpen = true
        view.render(model.state, rows: [])
        model.refresh()
        window.makeFirstResponder(view.field)
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        model.stop()
        view?.removeFromSuperview()
        view = nil
        isOpen = false
        outsideClicks.map(NSEvent.removeMonitor)
        outsideClicks = nil
        onOpenChange?(false)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        model.setText(view?.field.stringValue ?? "")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let fieldIsEmpty = view?.field.stringValue.isEmpty ?? true
        switch selector {
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveLeft(_:)) where fieldIsEmpty: model.moveChip(by: -1)
        case #selector(NSResponder.moveRight(_:)) where fieldIsEmpty: model.moveChip(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            run(forking: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func run(forking: Bool) {
        guard let plan = model.plan(forking: forking) else { return }
        let directory = model.selectedDirectory
        if case .open = plan { close() }
        open(plan, directory)
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard event.window === window, let view else { return }
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { close() }
    }
}
