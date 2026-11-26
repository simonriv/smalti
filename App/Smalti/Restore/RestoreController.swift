import AppKit
import OSLog
import SmaltiCore

/// What the user chose on "Retomar donde quedaste".
enum RestoreChoice: Equatable {
    case restore(RestoreSelection)
    case layoutsOnly
    case startClean
    /// F6: restore what is checked, then open a session from the search column in a new pane.
    case restoreAndOpen(RestoreSelection, OpenPlan, directory: String?)
}

/// Primary adapter for the resume screen: keeps the selection and the highlighted row, turns keys and clicks into a
/// `RestoreChoice`, and toggles "Siempre restaurar" in the store. Every action has a key (↑↓, espacio, ↵, ⌘L, esc, ⌘,).
/// F6: Tab moves between the list and the session search; in the search, esc gives the focus back and never discards
/// the saved session, and ↩ restores what is checked and then opens the session (⌘↩ forks it).
@MainActor
final class RestoreController: NSObject, NSTextFieldDelegate {
    struct Content {
        let snapshot: SessionSnapshot
        /// F4.5: grouped by window ("Ventana 1 · 2 workspaces") when the session had two or more.
        let windows: [ResumeWindow]
        /// "anoche a las 23:48".
        let closedAt: String
    }

    let view: RestoreView
    private let content: Content
    private let preferences: any RestorePreferenceStore
    private let onChoice: (RestoreChoice) -> Void
    private var selection: RestoreSelection
    private var highlighted = 0
    private var rowIDs: [UUID] { content.windows.flatMap(\.workspaces).flatMap(\.rows).map(\.id) }
    private let sessions: SessionSearchModel
    private var notice: String?
    /// The screen answers once: a second ↩ queued while the search settled does nothing.
    private var hasChosen = false

    init(
        _ content: Content, theme: Theme, preferences: any RestorePreferenceStore, sessions: SessionSearchModel,
        onChoice: @escaping (RestoreChoice) -> Void
    ) {
        self.content = content
        self.preferences = preferences
        self.onChoice = onChoice
        selection = .defaults(for: content.snapshot)
        view = RestoreView(theme: theme, windows: content.windows, closedAt: content.closedAt)
        self.sessions = sessions
        super.init()
        view.onKey = { [weak self] key in self?.handle(key) ?? false }
        view.onToggleRow = { [weak self] id in self?.toggle(id) }
        view.onAction = { [weak self] action in self?.perform(action) }
        view.search.field.delegate = self
        view.search.onChip = { [weak self] index in self?.sessions.selectChip(index) }
        view.search.onCommandReturn = { [weak self] in
            guard let self, isSearchFocused else { return }
            sessions.whenSettled { [weak self] in self?.openSession(forking: true) }
        }
        view.search.onClickRow = { [weak self] id in
            self?.sessions.select(id: id)
            self?.openSession(forking: false)
        }
        sessions.onChange = { [weak self] in self?.renderSessions() }
        render()
        renderSessions()
        sessions.refresh()
    }

    /// The screen is leaving: the search stops reading the harnesses.
    func stop() { sessions.stop() }

    // MARK: - Session search column (F6)

    func controlTextDidChange(_ notification: Notification) {
        notice = nil
        sessions.setText(view.search.field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let fieldIsEmpty = view.search.field.stringValue.isEmpty
        switch selector {
        case #selector(NSResponder.moveUp(_:)): sessions.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): sessions.moveSelection(by: 1)
        case #selector(NSResponder.moveLeft(_:)) where fieldIsEmpty: sessions.moveChip(by: -1)
        case #selector(NSResponder.moveRight(_:)) where fieldIsEmpty: sessions.moveChip(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            sessions.whenSettled { [weak self] in self?.openSession(forking: false) }
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.insertBacktab(_:)):
            focusList()
        default: return false
        }
        return true
    }

    /// ⌘↩ forks only from the search column; on the list it means nothing.
    private var isSearchFocused: Bool {
        (view.window?.firstResponder as? NSTextView)?.delegate === view.search.field
    }

    private func focusSearch() {
        view.window?.makeFirstResponder(view.search.field)
    }

    private func focusList() {
        view.window?.makeFirstResponder(view)
    }

    private func openSession(forking: Bool) {
        guard let plan = sessions.plan(forking: forking) else { return }
        if case .cannotFork(let harness) = plan {
            notice = OpenHarnessSession.cannotForkMessage(harness, texts: .current)
            renderSessions()
            return
        }
        guard !hasChosen else { return }
        hasChosen = true
        onChoice(.restoreAndOpen(selection, plan, directory: sessions.selectedDirectory))
    }

    private func renderSessions() {
        view.search.render(sessions.state, rows: sessions.rows(), notice: notice)
    }

    enum Action {
        case restore, layoutsOnly, startClean, toggleAlways
    }

    private func handle(_ key: RestoreKey) -> Bool {
        switch key {
        case .down: highlighted = min(highlighted + 1, max(rowIDs.count - 1, 0))
        case .up: highlighted = max(highlighted - 1, 0)
        case .toggle: if rowIDs.indices.contains(highlighted) { toggle(rowIDs[highlighted]) }
        case .restore: perform(.restore)
        case .layoutsOnly: perform(.layoutsOnly)
        case .startClean: perform(.startClean)
        case .toggleAlways: perform(.toggleAlways)
        case .switchColumn: focusSearch()
        }
        render()
        return true
    }

    private func toggle(_ id: UUID) {
        selection = selection.toggling(id)
        if let index = rowIDs.firstIndex(of: id) { highlighted = index }
        render()
    }

    private func perform(_ action: Action) {
        switch action {
        case .restore: onChoice(.restore(selection))
        case .layoutsOnly: onChoice(.layoutsOnly)
        case .startClean: onChoice(.startClean)
        case .toggleAlways:
            let next: RestorePreference = preferences.current() == .always ? .ask : .always
            do {
                try preferences.set(next)
            } catch {
                // The checkbox keeps showing the stored value, so the screen stays truthful.
                Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "restore")
                    .error("could not save the restore preference: \(error.summary(.english), privacy: .public)")
            }
            render()
        }
    }

    private func render() {
        view.render(
            .init(
                checked: Set(rowIDs.filter(selection.isChecked)),
                highlighted: rowIDs.indices.contains(highlighted) ? rowIDs[highlighted] : nil,
                restoreCount: selection.checkedCount(in: content.snapshot),
                alwaysRestore: preferences.current() == .always))
    }
}

/// Keys the resume screen understands.
enum RestoreKey {
    case up, down, toggle, restore, layoutsOnly, startClean, toggleAlways, switchColumn

    private static let keyCodes: [UInt16: RestoreKey] = [
        126: .up, 125: .down, 49: .toggle, 36: .restore, 76: .restore, 53: .startClean, 48: .switchColumn,
    ]

    /// Arrow and keypad keys carry these flags by themselves.
    private static let inherentFlags: NSEvent.ModifierFlags = [.function, .numericPad]

    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(Self.inherentFlags)
        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "l": self = .layoutsOnly
            case ",": self = .toggleAlways
            default: return nil
            }
            return
        }
        guard let key = Self.keyCodes[event.keyCode], modifiers.isEmpty || Self.isSynthesizedSpace(event, modifiers)
        else { return nil }
        self = key
    }

    /// XCUITest types a space as ⌃Space on the Latin American layout (KB gotcha); a real ⌃Space never reaches the
    /// app because macOS keeps it for switching input sources.
    private static func isSynthesizedSpace(_ event: NSEvent, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        event.keyCode == 49 && modifiers == .control
    }
}
