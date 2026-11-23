import AppKit
import SmaltiCore

/// Shows the Tab menu over the pane, at the cursor, and turns its effects into answers to zsh. While it is open it
/// takes ↑ ↓ ⇥ ↩ esc from the keyboard (only in its own pane); everything else reaches zsh, whose new line
/// refilters or closes it. It closes as soon as the shell is no longer at its prompt.
@MainActor
final class CompletionMenuController {
    private let coordinator: InputCoordinator
    private let provider: any TerminalViewProvider
    private let theme: () -> Theme
    private let focusedPane: () -> PaneID?
    private var menu = CompletionMenu()
    private var request: InputCoordinator.Request?
    private var view: CompletionMenuView?
    private var promptWatch: Timer?

    init(
        coordinator: InputCoordinator, provider: any TerminalViewProvider,
        context: (theme: () -> Theme, focusedPane: () -> PaneID?)
    ) {
        self.coordinator = coordinator
        self.provider = provider
        theme = context.theme
        focusedPane = context.focusedPane
        coordinator.onMenu = { [weak self] request, line, result in self?.open(request, line: line, result: result) }
        coordinator.onGenerated = { [weak self] request, line, items in
            guard request.pane == self?.request?.pane else { return }
            self?.apply(self?.menu.addGenerated(items, for: line) ?? .none)
        }
        coordinator.onLine = { [weak self] pane, line in
            guard pane == self?.request?.pane else { return }
            self?.apply(self?.menu.lineChanged(line) ?? .none)
        }
    }

    var isOpen: Bool { view != nil }

    /// True when the menu used the key.
    func handle(_ event: NSEvent) -> Bool {
        guard isOpen, event.type == .keyDown, let pane = request?.pane, focusedPane() == pane else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            let key = Self.menuKey(event.keyCode)
        else { return false }
        apply(menu.press(key))
        return true
    }

    func close() {
        menu = CompletionMenu()
        hide()
        request = nil
    }

    private func open(_ request: InputCoordinator.Request, line: InputLine, result: CompletionResult) {
        close()
        self.request = request
        menu.request(for: line)
        apply(menu.receive(result.items, for: line, generating: result.hasGenerators))
    }

    private func apply(_ effect: MenuEffect) {
        guard let request else { return }
        switch effect {
        case .none: return
        case .show: render()
        case .close: close()
        case .insert(let line):
            coordinator.send({ .edit(seq: $0, line) }, to: request)
            close()
        case .insertThenShow(let line):
            coordinator.send({ .edit(seq: $0, line) }, to: request)
            render()
        case .fallback:
            coordinator.send({ .fallback(seq: $0) }, to: request)
            close()
        }
    }

    private func render() {
        guard let request, provider.isAtPrompt(request.pane), let host = provider.view(for: request.pane),
            let cell = provider.cursorCell(request.pane), !menu.visible.isEmpty
        else { return close() }
        let menuView = view ?? CompletionMenuView(theme: theme())
        let frame = MenuPlacement.frame(
            cursor: cell, pane: Size(width: host.bounds.width, height: host.bounds.height), rows: menu.visible.count,
            tokens: theme().inputMenu)
        // `cursorCell` counts from the top; the terminal view counts from the bottom unless it is flipped.
        let y = host.isFlipped ? frame.origin.y : host.bounds.height - frame.origin.y - frame.size.height
        menuView.frame = NSRect(x: frame.origin.x, y: y, width: frame.size.width, height: frame.size.height)
        menuView.show(menu.visible, selected: menu.selected)
        if menuView.superview !== host { host.addSubview(menuView) }
        view = menuView
        watchPrompt()
    }

    private func hide() {
        view?.removeFromSuperview()
        view = nil
        promptWatch?.invalidate()
        promptWatch = nil
    }

    /// A command that starts (or a full-screen program) closes the menu even without a key press.
    private func watchPrompt() {
        guard promptWatch == nil else { return }
        promptWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pane = self.request?.pane else { return }
                if !self.provider.isAtPrompt(pane) { self.close() }
            }
        }
    }

    private static func menuKey(_ keyCode: UInt16) -> MenuKey? {
        switch keyCode {
        case 126: .up
        case 125: .down
        case 48: .tab
        case 36, 76: .enter
        case 53: .escape
        default: nil
        }
    }
}
