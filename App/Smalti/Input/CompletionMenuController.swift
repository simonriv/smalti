import AppKit
import SmaltiCore

/// Shows the Tab menu over the pane, at the cursor, and turns its effects into answers to zsh.
///
/// It only takes keys while the pane's terminal has the keyboard (not under ⌘K, ⌃R or the observatory): ↑ ↓ ⇥ ↩
/// and esc are the menu's; any other key closes it and reaches zsh, except letters and ⌫, which reach zsh and
/// refilter it through the new line. It closes as soon as the shell leaves its prompt, and follows the pane's
/// size.
@MainActor
final class CompletionMenuController {
    private let coordinator: InputCoordinator
    private let provider: any TerminalViewProvider
    private let theme: () -> Theme
    private var menu = CompletionMenu()
    private var request: InputCoordinator.Request?
    private var view: CompletionMenuView?
    private var promptWatch: Timer?
    private var resizes: NSObjectProtocol?
    private var clicks: Any?

    init(coordinator: InputCoordinator, provider: any TerminalViewProvider, theme: @escaping () -> Theme) {
        self.coordinator = coordinator
        self.provider = provider
        self.theme = theme
        coordinator.onMenu = { [weak self] request, line, result in self?.open(request, line: line, result: result) }
        coordinator.onGenerated = { [weak self] request, line, items in
            guard let self, request == self.request else { return }
            self.apply(self.menu.addGenerated(items, for: line))
        }
        coordinator.onLine = { [weak self] pane, line in
            guard let self, pane == self.request?.pane else { return }
            self.apply(self.menu.lineChanged(line))
        }
    }

    var isOpen: Bool { view != nil }

    /// True when the menu used the key.
    func handle(_ event: NSEvent) -> Bool {
        guard isOpen, event.type == .keyDown, let pane = request?.pane, let terminal = provider.view(for: pane),
            terminal.window?.firstResponder === terminal
        else { return false }
        // A command may have started since the last prompt check: its keys are never the menu's.
        guard provider.isAtPrompt(pane) else {
            close()
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, let key = Self.menuKey(event.keyCode) else {
            if !Self.edits(event, modifiers: modifiers) { apply(menu.press(.other)) }
            return false
        }
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
        guard let request else { return }
        guard !menu.visible.isEmpty else { return close() }
        guard provider.isAtPrompt(request.pane), let host = provider.view(for: request.pane),
            let cell = provider.cursorCell(request.pane)
        else {
            // The menu cannot show (no cursor cell, no view): zsh's own Tab instead, unless the menu was already up.
            if view == nil { coordinator.send({ .fallback(seq: $0) }, to: request) }
            return close()
        }
        let isNew = view == nil
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
        if isNew {
            Appearing.fadeIn(menuView, duration: theme().motion.overlayAppearDuration)
            watch(host)
        }
    }

    private func hide() {
        view?.removeFromSuperview()
        view = nil
        promptWatch?.invalidate()
        promptWatch = nil
        resizes.map(NotificationCenter.default.removeObserver)
        resizes = nil
        clicks.map(NSEvent.removeMonitor)
        clicks = nil
    }

    /// A command that starts (or a full-screen program) closes the menu even without a key press; a resize or a
    /// font change places it again.
    private func watch(_ host: NSView) {
        promptWatch = Timer.scheduledTimer(withTimeInterval: PromptWatch.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pane = self.request?.pane else { return }
                if !self.provider.isAtPrompt(pane) { self.close() }
            }
        }
        // The menu takes no clicks: any click (another pane, the same one, elsewhere) closes it and goes through.
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.close() }
            return event
        }
        host.postsFrameChangedNotifications = true
        resizes = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: host, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private static func menuKey(_ keyCode: UInt16) -> MenuKey? {
        switch keyCode {
        case KeyCode.upArrow: .up
        case KeyCode.downArrow: .down
        case KeyCode.tab: .tab
        case KeyCode.returnKey, KeyCode.keypadEnter: .enter
        case KeyCode.escape: .escape
        default: nil
        }
    }

    /// Typing (characters without ⌘ or ⌃) and ⌫ change the line: zsh's next `line` refilters the menu.
    private static func edits(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        if event.keyCode == KeyCode.delete { return modifiers.isEmpty }
        guard modifiers.isDisjoint(with: [.command, .control]), let text = event.characters, !text.isEmpty else {
            return false
        }
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && Self.menuKey(event.keyCode) == nil
    }
}

/// The overlays' appearance: a fade of at most 150 ms, none with "Reducir movimiento".
@MainActor
enum Appearing {
    static func fadeIn(_ view: NSView, duration: Double) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, duration > 0 else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view.animator().alphaValue = 1
        }
    }
}
