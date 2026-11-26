import Foundation
import SmaltiCore
import Testing

import TOMLConfigAdapter

/// Spec F5, `theme.toml`: read over `config.toml` key by key, with its own allowed tables and values.
@MainActor
@Suite("theme.toml reading")
struct ThemeReaderTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-theme-\(UUID())")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func store(config: String? = nil, theme: String?) throws -> TOMLConfigStore {
        let configFile = directory.appending(path: "config.toml")
        let themeFile = directory.appending(path: "theme.toml")
        if let config { try config.write(to: configFile, atomically: true, encoding: .utf8) }
        if let theme { try theme.write(to: themeFile, atomically: true, encoding: .utf8) }
        return TOMLConfigStore(config: configFile, theme: themeFile)
    }

    private var themePath: String { directory.appending(path: "theme.toml").path(percentEncoded: false) }

    @Test func missingThemeFileKeepsConfig() throws {
        let config = try store(config: "[appearance]\nblur = 10\n", theme: nil).reload()

        #expect(config.appearance.blur == 10)
    }

    @Test func themeWinsOverConfigPerKey() throws {
        let config = try store(
            config: "[appearance]\nblur = 10\nglass_opacity = 0.5\n", theme: "[appearance]\nblur = 20\n"
        ).reload()

        #expect(config.appearance.blur == 20)
        #expect(config.appearance.glassOpacity == 0.5)
    }

    @Test func duplicatedKeysAreWarned() throws {
        let store = try store(
            config: "[appearance]\nblur = 10\n[prompt]\nsymbol = \"$\"\n",
            theme: "[appearance]\nblur = 20\ngap = 4\n[prompt]\nsymbol = \"λ\"\n")

        _ = try store.reload()

        #expect(store.warnings() == [.duplicatedKeys(["appearance.blur", "prompt.symbol"])])
    }

    @Test func noDuplicatesNoWarning() throws {
        let store = try store(config: "[appearance]\nblur = 10\n", theme: "[appearance]\ngap = 4\n")

        _ = try store.reload()

        #expect(store.warnings().isEmpty)
    }

    @Test func everyThemeKeyIsRead() throws {
        let text = """
            [appearance]
            theme = "ambar-nocturno"
            protect_legibility = false

            [appearance.ansi.bosque]
            1 = "#ff6b6b"
            15 = "#ffffff"

            [window]
            buttons = "hover"

            [prompt]
            source = "shell"
            style = "symbol-only"
            layout = "one-line"
            modules = ["time", "directory"]
            icons = "nerd"
            symbol = "❯"
            """

        let config = try store(theme: text).reload()

        #expect(config.appearance.theme == .ambarNocturno)
        #expect(!config.appearance.protectLegibility)
        #expect(
            config.appearance.ansiOverrides[.bosque]?.colors == [
                1: try RGBAColor(hex: "#ff6b6b"), 15: try RGBAColor(hex: "#ffffff"),
            ])
        #expect(config.window.buttons == .hover)
        #expect(
            config.prompt
                == PromptConfig(
                    source: .shell, style: .symbolOnly, layout: .oneLine, modules: [.time, .directory], icons: .nerd,
                    symbol: .heavyChevron))
    }

    @Test func invalidAnsiIndexNamesLine() throws {
        let store = try store(theme: "[appearance.ansi.bosque]\n16 = \"#ffffff\"\n")

        #expect(
            throws: ConfigError(file: themePath, line: 2, key: "16", problem: .expectedANSIIndex)
        ) {
            try store.reload()
        }
    }

    @Test func invalidAnsiColorNamesKey() throws {
        let store = try store(theme: "[appearance.ansi.bosque]\n3 = \"rojo\"\n")

        #expect(throws: ConfigError(file: themePath, line: 2, key: "3", problem: .expectedColor)) {
            try store.reload()
        }
    }

    @Test func unknownThemeIsRejected() throws {
        let store = try store(theme: "[appearance]\ntheme = \"solarizado\"\n")

        #expect(
            throws: ConfigError(
                file: themePath, line: 2, key: "theme",
                problem: .unknownTheme(["obsidiana", "niebla", "ambar-nocturno", "bosque"]))
        ) {
            try store.reload()
        }
    }

    @Test func unknownAnsiThemeIsRejected() throws {
        let store = try store(theme: "[appearance.ansi.solarizado]\n1 = \"#ffffff\"\n")

        #expect(throws: ConfigError.self) { try store.reload() }
    }

    @Test func unknownModuleIsRejected() throws {
        let store = try store(theme: "[prompt]\nmodules = [\"directory\", \"weather\"]\n")

        #expect(throws: ConfigError(file: themePath, line: 2, key: "modules", problem: .unknownModule("weather"))) {
            try store.reload()
        }
    }

    @Test func repeatedModuleIsRejected() throws {
        let store = try store(theme: "[prompt]\nmodules = [\"time\", \"time\"]\n")

        #expect(throws: ConfigError(file: themePath, line: 2, key: "modules", problem: .repeatedModule("time"))) {
            try store.reload()
        }
    }

    @Test func confirmCloseStaysInConfig() throws {
        let themeStore = try store(theme: "[window]\nconfirm_close = false\n")

        #expect(throws: ConfigError(file: themePath, line: 2, key: "confirm_close", problem: .unknownKey)) {
            try themeStore.reload()
        }
    }

    @Test func otherTablesAreNotAllowedInTheme() throws {
        let store = try store(theme: "[shell]\ncommand = \"/bin/zsh\"\n")

        #expect(throws: ConfigError(file: themePath, line: 1, key: "shell", problem: .unknownTable)) {
            try store.reload()
        }
    }

    @Test func configFileStillAcceptsButtonsAndPrompt() throws {
        let config = try store(config: "[window]\nbuttons = \"visible\"\n[prompt]\nicons = \"none\"\n", theme: nil)
            .reload()

        #expect(config.window.buttons == .visible)
        #expect(config.prompt.icons == PromptIcons.none)
    }

    @Test func invalidValuesNameTheirKey() throws {
        let store = try store(theme: "[window]\nbuttons = \"siempre\"\n")

        #expect(
            throws: ConfigError(
                file: themePath, line: 2, key: "buttons", problem: .expectedOneOf(["hidden", "hover", "visible"]))
        ) {
            try store.reload()
        }
    }
}
