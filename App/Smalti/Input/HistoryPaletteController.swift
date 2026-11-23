import AppKit
import SmaltiCore

/// The ⌃R palette over the pane: searches as the user types, ⇥ switches between "Este directorio" and "Todos",
/// ↩ puts the chosen command on zsh's line, ⌘↩ also runs it (Return is typed only once the `edit` went out whole,
/// so the old line never runs by mistake), esc closes leaving the line as it was.
@MainActor
final class HistoryPaletteController: NSObject, NSTextFieldDelegate {
    private let coordinator: InputCoordinator
    private let provider: any TerminalViewProvider
    private let theme: () -> Theme
    private let returnFocus: (PaneID) -> Void
    private var request: InputCoordinator.Request?
    private var view: HistoryPaletteView?
    private var hits: [HistoryHit] = []
    private var selected = 0
    private var isEverywhere = false
    private var searchID = 0

    init(
        coordinator: InputCoordinator, provider: any TerminalViewProvider,
        context: (theme: () -> Theme, returnFocus: (PaneID) -> Void)
    ) {
        self.coordinator = coordinator
        self.provider = provider
        theme = context.theme
        returnFocus = context.returnFocus
        super.init()
        coordinator.onHistory = { [weak self] request, query in self?.open(request, query: query) }
    }

    var isOpen: Bool { view != nil }

    /// ⌘↩ is also a Smalti shortcut; while the palette is open it is the palette's.
    func handle(_ event: NSEvent) -> Bool {
        guard isOpen, event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        else { return false }
        choose(running: true)
        return true
    }

    func close() {
        guard let request, let view else { return }
        view.removeFromSuperview()
        self.view = nil
        self.request = nil
        returnFocus(request.pane)
    }

    private func open(_ request: InputCoordinator.Request, query: String) {
        close()
        guard let host = provider.view(for: request.pane) else { return }
        self.request = request
        isEverywhere = false
        let palette = HistoryPaletteView(theme: theme())
        palette.field.stringValue = query
        palette.field.delegate = self
        palette.onCommandReturn = { [weak self] in self?.choose(running: true) }
        let width = min(max(host.bounds.width * 0.86, 480), 720)
        palette.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(palette)
        NSLayoutConstraint.activate([
            palette.widthAnchor.constraint(equalToConstant: min(width, host.bounds.width)),
            palette.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            palette.topAnchor.constraint(equalTo: host.topAnchor, constant: 26),
        ])
        view = palette
        palette.window?.makeFirstResponder(palette.field)
        search()
    }

    func controlTextDidChange(_ notification: Notification) {
        selected = 0
        search()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertTab(_:)):
            isEverywhere.toggle()
            selected = 0
            search()
        case #selector(NSResponder.insertNewline(_:)):
            choose(running: false)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func move(by step: Int) {
        guard !hits.isEmpty else { return }
        selected = (selected + step + hits.count) % hits.count
        render()
    }

    private func choose(running: Bool) {
        guard let request, hits.indices.contains(selected) else { return close() }
        let command = hits[selected].stats.command
        let line = InputLine(text: command, cursor: command.unicodeScalars.count)
        let sent = coordinator.send({ .edit(seq: $0, line) }, to: request)
        close()
        if running && sent { coordinator.pressReturn(in: request.pane) }
    }

    private func search() {
        guard let request, let view else { return }
        searchID += 1
        let id = searchID
        let query = view.field.stringValue
        let everywhere = isEverywhere
        Task { [weak self, coordinator] in
            let found = await coordinator.search(query, in: request.pane, everywhere: everywhere)
            guard let self, self.searchID == id else { return }
            self.hits = found
            self.selected = min(self.selected, max(found.count - 1, 0))
            self.render()
        }
    }

    private func render() {
        guard let view else { return }
        view.showScope(everywhere: isEverywhere)
        view.show(hits, selected: selected, now: .now, isHistoryEmpty: hits.isEmpty && view.field.stringValue.isEmpty)
    }
}
