import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5, "Cuándo se guarda": Apariencia applies at once and writes `theme.toml` 300 ms after the last change.
@MainActor
@Suite("ChangeAppearance")
struct ChangeAppearanceTests {
    private let store = InMemoryAppearanceStore()
    private let debouncer = ManualDebouncer()

    private func make() -> ChangeAppearance {
        ChangeAppearance(document: AppearanceDocument(config: .defaults), store: store, debouncer: debouncer)
    }

    @Test func saveDelayIs300Milliseconds() {
        #expect(ChangeAppearance.saveDelay == .milliseconds(300))
    }

    @Test func changeAppliesAtOnce() {
        let change = make()

        let applied = change.apply { $0.appearance.glassOpacity = 0.8 }

        #expect(applied.theme.window.background.alpha == 0.8)
        #expect(change.document.appearance.glassOpacity == 0.8)
    }

    @Test func sliderDragSavesOnceAfter300ms() {
        let change = make()
        for value in stride(from: 0.62, through: 0.80, by: 0.02) {
            _ = change.apply { $0.appearance.glassOpacity = value }
        }
        #expect(store.saved.isEmpty)

        debouncer.fire()

        #expect(store.saved.count == 1)
        #expect(store.saved.last?.appearance.glassOpacity == change.document.appearance.glassOpacity)
    }

    @Test func applyWithoutChangesDoesNotSave() {
        let change = make()

        _ = change.apply { $0.appearance.glassOpacity = 0.62 }
        debouncer.fire()

        #expect(store.saved.isEmpty)
    }

    @Test func selectingThemeClearsAccent() throws {
        var config = SmaltiConfig.defaults
        config.appearance.accent = try RGBAColor(hex: "#ff0000")
        let change = ChangeAppearance(document: AppearanceDocument(config: config), store: store, debouncer: debouncer)

        let applied = change.selectTheme(.bosque)

        #expect(change.document.appearance.accent == nil)
        #expect(change.document.appearance.theme == .bosque)
        #expect(applied.theme.accent == (try RGBAColor(hex: "#6fd3b5")))
    }

    @Test func saveNowWritesWithoutWaiting() {
        let change = make()
        _ = change.apply { $0.buttons = .visible }

        change.saveNow()

        #expect(store.saved.last?.buttons == .visible)
    }

    @Test func reloadReplacesDocumentWithoutSaving() {
        let change = make()
        var config = SmaltiConfig.defaults
        config.window.buttons = .hover

        change.reload(AppearanceDocument(config: config))
        debouncer.fire()

        #expect(change.document.buttons == .hover)
        #expect(store.saved.isEmpty)
    }

    @Test func saveFailureIsReported() {
        store.failure = ConfigError(file: "theme.toml", line: nil, key: "", reason: "disco lleno")
        var reported: [ConfigError] = []
        let change = ChangeAppearance(
            document: AppearanceDocument(config: .defaults), store: store, debouncer: debouncer,
            onSaveError: { reported.append($0) })

        _ = change.apply { $0.appearance.blur = 10 }
        debouncer.fire()

        #expect(reported.map(\.reason) == ["disco lleno"])
    }

    @Test func documentGoesBackIntoConfig() {
        var config = SmaltiConfig.defaults
        var document = AppearanceDocument(config: config)
        document.buttons = .visible
        document.prompt.symbol = .lambda

        config = document.applied(to: config)

        #expect(config.window.buttons == .visible)
        #expect(config.prompt.symbol == .lambda)
        #expect(config.window.confirmClose)
    }

    @Test func inMemoryStoreHonorsTheContract() {
        AppearanceStoreContract.verify {
            let store = InMemoryAppearanceStore()
            return (store, { store.saved.last })
        }
    }
}

/// Block 2 review (M1): a reload or an immediate save cancels the pending write.
@MainActor
@Suite("ChangeAppearance · review")
struct ChangeAppearanceReviewTests {
    private let store = InMemoryAppearanceStore()
    private let debouncer = ManualDebouncer()

    @Test func reloadCancelsPendingSave() {
        let change = ChangeAppearance(
            document: AppearanceDocument(config: .defaults), store: store, debouncer: debouncer)
        _ = change.apply { $0.appearance.blur = 10 }

        change.reload(AppearanceDocument(config: .defaults))
        debouncer.fire()

        #expect(store.saved.isEmpty)
    }

    @Test func studioApplySavesOnce() {
        let change = ChangeAppearance(
            document: AppearanceDocument(config: .defaults), store: store, debouncer: debouncer)
        let edit = EditPrompt(appearance: change)
        edit.draft.symbol = .dollar

        edit.apply()
        debouncer.fire()

        #expect(store.saved.count == 1)
    }
}
