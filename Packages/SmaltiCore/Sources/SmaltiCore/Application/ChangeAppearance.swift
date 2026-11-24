/// Apariencia (spec F5): every change applies at once; `theme.toml` is written once the user stops for
/// `saveDelay`, so a slider drag is one write.
@MainActor
public final class ChangeAppearance {
    public static let saveDelay = Duration.milliseconds(300)

    public private(set) var document: AppearanceDocument
    private let store: any AppearanceStore
    private let debouncer: any Debouncer
    private let onSaveError: @MainActor (ConfigError) -> Void
    /// A change waits for its debounced write.
    private var isSavePending = false

    public init(
        document: AppearanceDocument, store: any AppearanceStore, debouncer: any Debouncer,
        onSaveError: @escaping @MainActor (ConfigError) -> Void = { _ in }
    ) {
        self.document = document
        self.store = store
        self.debouncer = debouncer
        self.onSaveError = onSaveError
    }

    /// What is painted after the change; a change that leaves the document equal schedules nothing.
    @discardableResult
    public func apply(_ change: (inout AppearanceDocument) -> Void) -> AppliedTheme {
        var updated = document
        change(&updated)
        if updated != document {
            document = updated
            isSavePending = true
            debouncer.schedule { [weak self] in self?.saveNow() }
        }
        return ThemeCatalog.apply(document.appearance)
    }

    /// Choosing a theme in the UI drops a TOML accent: the theme comes whole.
    @discardableResult
    public func selectTheme(_ id: ThemeID) -> AppliedTheme {
        apply {
            $0.appearance.theme = id
            $0.appearance.accent = nil
        }
    }

    public func saveNow() {
        debouncer.cancel()
        isSavePending = false
        do {
            try store.save(document)
        } catch {
            onSaveError(error)
        }
    }

    /// Quitting (block 4 review, I1): the change of the last 300 ms is written; with none pending, nothing is.
    public func saveIfPending() {
        guard isSavePending else { return }
        saveNow()
    }

    /// The file changed outside the UI ("Recargar configuración"): show it, do not write it back.
    public func reload(_ document: AppearanceDocument) {
        debouncer.cancel()
        isSavePending = false
        self.document = document
    }
}
