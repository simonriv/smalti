import AppKit
import OSLog
import SmaltiCore

/// What the user chose on "Retomar donde quedaste".
enum RestoreChoice: Equatable {
    case restore(RestoreSelection)
    case layoutsOnly
    case startClean
}

/// Primary adapter for the resume screen: keeps the selection and the highlighted row, turns keys and clicks into a
/// `RestoreChoice`, and toggles "Siempre restaurar" in the store. Every action has a key (↑↓, espacio, ↵, ⌘L, esc, ⌘,).
@MainActor
final class RestoreController {
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

    init(
        _ content: Content, theme: Theme, preferences: any RestorePreferenceStore,
        onChoice: @escaping (RestoreChoice) -> Void
    ) {
        self.content = content
        self.preferences = preferences
        self.onChoice = onChoice
        selection = .defaults(for: content.snapshot)
        view = RestoreView(theme: theme, windows: content.windows, closedAt: content.closedAt)
        view.onKey = { [weak self] key in self?.handle(key) ?? false }
        view.onToggleRow = { [weak self] id in self?.toggle(id) }
        view.onAction = { [weak self] action in self?.perform(action) }
        render()
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
                    .error("could not save the restore preference: \(error.summary, privacy: .public)")
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
    case up, down, toggle, restore, layoutsOnly, startClean, toggleAlways

    private static let keyCodes: [UInt16: RestoreKey] = [
        126: .up, 125: .down, 49: .toggle, 36: .restore, 76: .restore, 53: .startClean,
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
