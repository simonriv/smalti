import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5, `theme.toml`: keys written in both files are reported by "Recargar configuración", and an edit made by
/// hand while the UI was open is kept when the UI saves.
@MainActor
@Suite("Config warnings and rebasing")
struct ConfigWarningTests {
    private final class WarningStore: ConfigStore {
        let warningsToReport: [ConfigWarning]

        init(_ warnings: [ConfigWarning]) {
            warningsToReport = warnings
        }

        func current() -> SmaltiConfig { .defaults }
        func reload() throws(ConfigError) -> SmaltiConfig { .defaults }
        func warnings() -> [ConfigWarning] { warningsToReport }
    }

    @Test func reloadCarriesTheStoreWarnings() {
        let store = WarningStore([.duplicatedKeys(["appearance.blur", "prompt.symbol"])])

        let reload = ReloadConfig(store: store).execute()

        #expect(reload.warnings == [.duplicatedKeys(["appearance.blur", "prompt.symbol"])])
    }

    @Test func duplicatedKeysMessageNamesThem() {
        let warning = ConfigWarning.duplicatedKeys(["appearance.blur", "prompt.symbol"])

        #expect(warning.message(.spanish) == "theme.toml manda sobre config.toml en: appearance.blur, prompt.symbol")
    }

    @Test func storesWithoutWarningsReportNone() {
        #expect(InMemoryConfigStore().warnings().isEmpty)
    }

    @Test func rebaseKeepsExternalEditAndUIChange() {
        let base = AppearanceDocument(config: .defaults)
        var ui = base
        ui.appearance.theme = .bosque
        var external = base
        external.appearance.blur = 12

        let merged = ui.rebased(onto: external, from: base)

        #expect(merged.appearance.theme == .bosque)
        #expect(merged.appearance.blur == 12)
    }

    @Test func uiWinsWhenBothChangedTheSameField() {
        let base = AppearanceDocument(config: .defaults)
        var ui = base
        ui.prompt.symbol = .lambda
        var external = base
        external.prompt.symbol = .dollar
        external.buttons = .visible

        let merged = ui.rebased(onto: external, from: base)

        #expect(merged.prompt.symbol == .lambda)
        #expect(merged.buttons == .visible)
    }

    @Test func rebaseWithoutExternalChangesIsTheUIDocument() {
        let base = AppearanceDocument(config: .defaults)
        var ui = base
        ui.appearance.radius = 4
        ui.prompt.modules = [.time]

        #expect(ui.rebased(onto: base, from: base) == ui)
    }
}
