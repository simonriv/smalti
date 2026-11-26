import AppKit
import GhosttyAdapter
import SmaltiCore

/// Primary adapter for the projects' overlays in one window (F8.5): the ⌘O selector and the confirmation card. Typing
/// filters, ↑↓ and ⌘O move, ↩ chooses, esc and a click outside close. What is listed, selected and said is the
/// domain's (`ProjectSelector`, `ProjectCard`); what choosing does is the app's (`choose`, `approve`).
@MainActor
final class ProjectsController: NSObject, NSTextFieldDelegate {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private var selector: ProjectSelector?
    private var recents: RecentProjectsView?
    private var card: ProjectConfirmView?
    private var shade: NSView?
    private var choose: ((String) -> Void)?
    private var outsideClicks: Any?
    /// ⌘O is the selector's while it is open: the keymap would reopen it.
    private var selectorKeys: Any?
    private var keymap = Keymap.standard

    init(window: SmaltiWindow) {
        self.window = window
    }

    func showRecents(
        _ selector: ProjectSelector, look: (theme: Theme, keymap: Keymap), choose: @escaping (String) -> Void
    ) {
        close()
        guard let content = window.contentView else { return }
        let theme = look.theme
        keymap = look.keymap
        let view = RecentProjectsView(theme: theme, nextKey: keymap.chord(for: .projectRecent)?.display)
        place(view, in: content, top: theme.palette.topOffset)
        view.field.delegate = self
        view.onClickRow = { [weak self] index in
            self?.update { $0.selecting(index) }
            self?.chooseSelected()
        }
        self.selector = selector
        self.choose = choose
        recents = view
        opened()
        view.render(selector)
        window.makeFirstResponder(view.field)
        selectorKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleSelectorKey(event) == true } ? nil : event
        }
    }

    /// The card over a dimmed window; `approve` runs on ↩, nothing on esc.
    func confirm(_ content: ProjectCardContent, theme: Theme, approve: @escaping () -> Void) {
        close()
        guard let host = window.contentView else { return }
        let shade = NSView()
        shade.wantsLayer = true
        shade.layer?.backgroundColor = theme.projects.shade.nsColor.cgColor
        shade.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(shade, positioned: .above, relativeTo: nil)
        OverlayBox.pin(shade, to: host)
        let view = ProjectConfirmView(content, theme: theme)
        place(view, in: host, top: theme.projects.confirmTopOffset)
        view.onCancel = { [weak self] in self?.close() }
        view.onConfirm = { [weak self] in
            self?.close()
            approve()
        }
        self.shade = shade
        card = view
        opened()
        window.makeFirstResponder(view)
    }

    func close() {
        guard isOpen else { return }
        [recents as NSView?, card, shade].forEach { $0?.removeFromSuperview() }
        recents = nil
        card = nil
        shade = nil
        selector = nil
        choose = nil
        [outsideClicks, selectorKeys].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        outsideClicks = nil
        selectorKeys = nil
        isOpen = false
        onOpenChange?(false)
    }

    private func place(_ view: NSView, in content: NSView, top: Double) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: top),
        ])
    }

    private func opened() {
        isOpen = true
        outsideClicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
            return event
        }
        onOpenChange?(true)
    }

    private func update(_ change: (ProjectSelector) -> ProjectSelector) {
        guard let selector else { return }
        let changed = change(selector)
        self.selector = changed
        recents?.render(changed)
    }

    private func chooseSelected() {
        guard let root = selector?.selectedRoot, let choose else { return }
        close()
        choose(root)
    }

    /// The chord of "Proyectos recientes…" (⌘O unless the TOML changed it) moves to the next project while the
    /// selector is open, in this window only; read like the KeyRouter reads it (review 2: Caps Lock, rebinding).
    private func handleSelectorKey(_ event: NSEvent) -> Bool {
        guard recents != nil, event.window === window, let chord = KeyChordTranslator.chord(from: event),
            keymap.command(for: chord) == .projectRecent
        else { return false }
        update { $0.moving(by: 1) }
        return true
    }

    private func closeIfOutside(_ event: NSEvent) {
        guard event.window === window, let view = recents ?? card else { return }
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { close() }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        let query = recents?.field.stringValue ?? ""
        update { $0.filtering(query) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): update { $0.moving(by: -1) }
        case #selector(NSResponder.moveDown(_:)): update { $0.moving(by: 1) }
        // Review 2: a held ↩ from ⌘K must not choose (and then confirm) a project by itself.
        case #selector(NSResponder.insertNewline(_:)):
            if ConfirmationKey.confirms(isRepeat: NSApp.currentEvent?.isARepeat ?? false) { chooseSelected() }
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }
}
