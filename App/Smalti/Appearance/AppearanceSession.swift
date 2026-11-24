import AppKit
import SmaltiCore
import TOMLConfigAdapter

/// The app's one Appearance document (spec F5): edits apply at once to every window through `onApply`, and
/// `theme.toml` is written 300 ms after the last one. "Recargar configuración" replaces the document with the files'.
@MainActor
final class AppearanceSession {
    private let change: ChangeAppearance
    private let store: TOMLAppearanceStore
    private let themeFile: URL
    /// Every window paints the new document (and the engine takes its terminal appearance).
    var onApply: ((AppearanceDocument) -> Void)?
    /// The open panels show the document again.
    var onRefresh: (() -> Void)?

    init(config: SmaltiConfig, themeFile: URL, onSaveError: @escaping @MainActor (ConfigError) -> Void) {
        let document = AppearanceDocument(config: config)
        let store = TOMLAppearanceStore(file: themeFile)
        store.remember(document)
        self.store = store
        self.themeFile = themeFile
        change = ChangeAppearance(
            document: document, store: store, debouncer: TimerDebouncer(delay: ChangeAppearance.saveDelay),
            onSaveError: onSaveError)
    }

    var state: AppearancePanelState {
        AppearancePanelState(
            document: change.document, applied: ThemeCatalog.apply(change.document.appearance),
            savedIn: AppearanceTexts.savedIn(path: themeFile.path(percentEncoded: false), home: Self.home))
    }

    private static var home: String {
        let path = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    func edit(_ edit: (inout AppearanceDocument) -> Void) {
        change.apply(edit)
        publish()
    }

    func selectTheme(_ id: ThemeID) {
        change.selectTheme(id)
        publish()
    }

    /// The files changed ("Recargar configuración"): show them; nothing is written back.
    func reload(_ config: SmaltiConfig) {
        let document = AppearanceDocument(config: config)
        store.remember(document)
        change.reload(document)
        onRefresh?()
    }

    /// "Abrir theme.toml": written first if it does not exist yet, so there is something to open.
    func openThemeFile() {
        if !FileManager.default.fileExists(atPath: themeFile.path(percentEncoded: false)) { change.saveNow() }
        URLOpener.open(themeFile)
    }

    /// Quitting: the change still waiting for its 300 ms is written.
    func saveIfPending() { change.saveIfPending() }

    private func publish() {
        onApply?(change.document)
        onRefresh?()
    }
}

/// `Debouncer` on the main run loop: only the last action scheduled within `delay` runs.
@MainActor
final class TimerDebouncer: Debouncer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
