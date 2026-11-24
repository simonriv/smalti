import SmaltiCore
import Testing

/// Keeps every saved document; `failure` makes the next saves throw.
@MainActor
public final class InMemoryAppearanceStore: AppearanceStore {
    public private(set) var saved: [AppearanceDocument] = []
    public var failure: ConfigError?
    /// A hand edit the file had when the next save came: it is merged in, as `TOMLAppearanceStore` does.
    public var handEdit: ((inout AppearanceDocument) -> Void)?

    public init() {}

    public func save(_ document: AppearanceDocument) throws(ConfigError) -> AppearanceDocument {
        if let failure { throw failure }
        var merged = document
        handEdit?(&merged)
        saved.append(merged)
        return merged
    }
}

/// Holds the last scheduled action until the test fires it.
@MainActor
public final class ManualDebouncer: Debouncer {
    private var pending: (@MainActor () -> Void)?

    public init() {}

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        pending = action
    }

    public func cancel() {
        pending = nil
    }

    public func fire() {
        let action = pending
        pending = nil
        action?()
    }
}

/// Every `AppearanceStore` gives back the document it saved.
public enum AppearanceStoreContract {
    @MainActor
    public static func verify(_ make: @MainActor () -> (any AppearanceStore, @MainActor () -> AppearanceDocument?)) {
        let (store, read) = make()
        var document = AppearanceDocument(config: .defaults)
        document.appearance.theme = .bosque
        document.buttons = .hover
        document.prompt = PromptConfig.standard.applying(.pills)
        do {
            try store.save(document)
        } catch {
            Issue.record("save failed: \(error)")
        }
        #expect(read() == document, "a saved document reads back unchanged")
    }
}
