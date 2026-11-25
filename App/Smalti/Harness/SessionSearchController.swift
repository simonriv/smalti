import AppKit
import OSLog
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
    /// ⌘↩ and ⌘1…⌘5 are the card's while it is open: the keymap and the terminal would take them first.
    private var cardKeys: Any?
    /// C7: the card opens in 100 ms or less with every store read; "sessions.open" spans the open until every harness
    /// answered. `-SmaltiSessionSearchTimings <file>` also writes each open's milliseconds (measurements only).
    private let signposter = OSSignposter(subsystem: AppIdentity.current.bundleIdentifier, category: "sessions")
    private let timings = UserDefaults.standard.string(forKey: "SmaltiSessionSearchTimings").map { URL(filePath: $0) }

    init(window: SmaltiWindow, model: SessionSearchModel, open: @escaping (OpenPlan, String?) -> Void) {
        self.window = window
        self.model = model
        self.open = open
    }

    func toggle(theme: Theme) {
        isOpen ? close() : show(theme: theme)
    }

    func show(theme: Theme) {
        guard !isOpen, let content = window.contentView else { return }
        let opened = ContinuousClock.now
        let interval = signposter.beginInterval("sessions.open")
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
        model.reset()
        view.field.delegate = self
        view.onCommandReturn = { [weak self] in self?.run(forking: true) }
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
        model.whenSettled { [weak self, timings] in
            self?.signposter.endInterval("sessions.open", interval)
            if let timings { TimingLog.append(since: opened, to: timings, label: "session search timings") }
        }
        window.makeFirstResponder(view.field)
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        cardKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleCardKey(event) == true } ? nil : event
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
        cardKeys.map(NSEvent.removeMonitor)
        cardKeys = nil
        onOpenChange?(false)
    }

    /// True when the key was the card's: ⌘↩ forks, ⌘1…⌘5 choose a chip. Only in this card's window.
    private func handleCardKey(_ event: NSEvent) -> Bool {
        guard isOpen, event.window === window else { return false }
        if HistoryPaletteView.isCommandReturn(event) {
            model.whenSettled { [weak self] in self?.run(forking: true) }
            return true
        }
        guard let chip = SessionSearchView.chipIndex(forCommandDigit: event) else { return false }
        model.selectChip(chip)
        return true
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
        case #selector(NSResponder.insertNewline(_:)): model.whenSettled { [weak self] in self?.run(forking: false) }
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func run(forking: Bool) {
        // A second ↩ queued before the listing settled finds the card already closed.
        guard isOpen, let plan = model.plan(forking: forking) else { return }
        let directory = model.selectedDirectory
        if case .open = plan { close() }
        open(plan, directory)
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard event.window === window, let view else { return }
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { close() }
    }
}
