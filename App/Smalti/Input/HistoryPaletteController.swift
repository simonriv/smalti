import AppKit
import SmaltiCore

/// The ⌃R palette over the pane: searches as the user types, ⇥ switches between "Este directorio" and "Todos",
/// ↩ puts the chosen command on zsh's line, ⌘↩ also runs it (an `editrun` followed by Return, typed only once the
/// edit went out whole; zsh refuses that Return if it dropped the edit), esc closes leaving the line as it was.
/// It also closes on a click outside it, when its field loses the keyboard, and when its pane leaves the prompt
/// or goes away.
@MainActor
final class HistoryPaletteController: NSObject, NSTextFieldDelegate {
    private let coordinator: InputCoordinator
    private let provider: any TerminalViewProvider
    private let theme: () -> Theme
    private let onOpen: () -> Void
    private let returnFocus: (PaneID) -> Void
    private var request: InputCoordinator.Request?
    private var view: HistoryPaletteView?
    private var hits: [HistoryHit] = []
    private var selected = 0
    private var isEverywhere = false
    private var isHistoryEmpty = false
    private var searchID = 0
    private var shownSearchID = 0
    /// ↩ or ⌘↩ pressed while the latest query was still searching: applied to its results, not the old ones.
    private var pendingChoice: Bool?
    private var outsideClicks: Any?
    private var promptWatch: Timer?

    init(
        coordinator: InputCoordinator, provider: any TerminalViewProvider,
        context: (theme: () -> Theme, onOpen: () -> Void, returnFocus: (PaneID) -> Void)
    ) {
        self.coordinator = coordinator
        self.provider = provider
        theme = context.theme
        onOpen = context.onOpen
        returnFocus = context.returnFocus
        super.init()
        coordinator.onHistory = { [weak self] request, query in self?.open(request, query: query) }
    }

    /// Open while its view is still in a window (its pane may have closed underneath).
    var isOpen: Bool { view?.window != nil }

    func isOpen(in window: NSWindow) -> Bool { view?.window === window }

    /// ⌘↩ is also a Smalti shortcut; while the palette is open it is the palette's.
    func handle(_ event: NSEvent) -> Bool {
        guard isOpen, event.type == .keyDown, HistoryPaletteView.isCommandReturn(event) else { return false }
        choose(running: true)
        return true
    }

    func close() {
        let pane = request?.pane
        view?.removeFromSuperview()
        view = nil
        request = nil
        pendingChoice = nil
        outsideClicks.map(NSEvent.removeMonitor)
        outsideClicks = nil
        promptWatch?.invalidate()
        promptWatch = nil
        if let pane { returnFocus(pane) }
    }

    private func open(_ request: InputCoordinator.Request, query: String) {
        close()
        guard let host = provider.view(for: request.pane) else { return }
        onOpen()
        self.request = request
        isEverywhere = false
        let palette = HistoryPaletteView(theme: theme())
        palette.field.stringValue = query
        palette.field.delegate = self
        palette.onCommandReturn = { [weak self] in self?.choose(running: true) }
        place(palette, in: host)
        view = palette
        Appearing.fadeIn(palette, duration: theme().motion.overlayAppearDuration)
        palette.window?.makeFirstResponder(palette.field)
        watch()
        search()
    }

    /// Centred, `widthFraction` of the pane between the minimum and the maximum (never wider than the pane), and
    /// it keeps that share when the pane resizes.
    private func place(_ palette: HistoryPaletteView, in host: NSView) {
        let tokens = theme().historyPalette
        palette.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(palette)
        let share = palette.widthAnchor.constraint(equalTo: host.widthAnchor, multiplier: tokens.widthFraction)
        share.priority = .defaultHigh
        let minimum = palette.widthAnchor.constraint(greaterThanOrEqualToConstant: tokens.minimumWidth)
        minimum.priority = .defaultHigh + 1
        NSLayoutConstraint.activate([
            share, minimum,
            palette.widthAnchor.constraint(lessThanOrEqualToConstant: tokens.maximumWidth),
            palette.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor),
            palette.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            palette.topAnchor.constraint(equalTo: host.topAnchor, constant: tokens.topOffset),
        ])
    }

    private func watch() {
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        promptWatch = Timer.scheduledTimer(withTimeInterval: PromptWatch.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pane = self.request?.pane else { return }
                if !self.isOpen || !self.provider.isAtPrompt(pane) { self.close() }
            }
        }
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard let view, event.window === view.window else { return }
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { close() }
    }

    func controlTextDidChange(_ notification: Notification) {
        selected = 0
        search()
    }

    /// The field lost the keyboard (another pane, another window): the palette goes with it.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let view, view.window?.firstResponder !== view.field.currentEditor() else { return }
        close()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.insertTab(_:)):
            isEverywhere.toggle()
            selected = 0
            search()
        case #selector(NSResponder.insertNewline(_:)): choose(running: false)
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
        guard shownSearchID == searchID else {
            pendingChoice = running
            return
        }
        guard let request, hits.indices.contains(selected) else { return close() }
        let command = hits[selected].stats.command
        let line = InputLine(text: command, cursor: command.unicodeScalars.count)
        let sent = coordinator.send({ .edit(seq: $0, line, thenEnter: running) }, to: request)
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
            let found = await coordinator.search(query, in: request, everywhere: everywhere)
            let isEmpty = await coordinator.isHistoryEmpty
            guard let self, self.searchID == id else { return }
            self.hits = found
            self.isHistoryEmpty = isEmpty
            self.selected = min(self.selected, max(found.count - 1, 0))
            self.shownSearchID = id
            self.render()
            if let running = self.pendingChoice {
                self.pendingChoice = nil
                self.choose(running: running)
            }
        }
    }

    private func render() {
        guard let view else { return }
        view.showScope(everywhere: isEverywhere)
        view.show(hits, selected: selected, now: .now, isHistoryEmpty: isHistoryEmpty)
    }
}
