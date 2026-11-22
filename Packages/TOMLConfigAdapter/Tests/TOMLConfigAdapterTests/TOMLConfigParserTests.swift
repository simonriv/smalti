import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

@Suite("TOMLConfigParser")
struct TOMLConfigParserTests {
    private static let file = "config.toml"

    private func parse(_ text: String) throws(ConfigError) -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: Self.file)
    }

    private func parseFixture(_ name: String) throws -> SmaltiConfig {
        try parse(try Fixture.text(name))
    }

    private func error(parsing text: String) -> ConfigError? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error
        }
    }

    private func error(parsingFixture name: String) throws -> ConfigError? {
        error(parsing: try Fixture.text(name))
    }

    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    // MARK: Values

    @Test func fullDefaultFileRoundTripsToDefaults() throws {
        let config = try parseFixture("defaults")

        #expect(config == .defaults)
    }

    @Test func emptyTextGivesDefaults() throws {
        let config = try parse("")

        #expect(config == .defaults)
    }

    @Test func customShellIsParsed() throws {
        let config = try parseFixture("custom-shell")

        #expect(config.shell == .custom("/bin/zsh -f"))
    }

    @Test func loginShellKeywordIsLoginShell() throws {
        let config = try parseFixture("login-shell")

        #expect(config.shell == .loginShell)
    }

    @Test func customAppearanceIsParsed() throws {
        let text = """
            [appearance]
            accent = "#ff8000"
            glass_opacity = 0.8
            blur = 12
            font_family = "Iosevka"
            font_size = 14.5
            gap = 6
            radius = 9
            """

        let appearance = try parse(text).appearance

        #expect(
            appearance
                == AppearanceSettings(
                    accent: RGBAColor(red: 255, green: 128, blue: 0, alpha: 1), glassOpacity: 0.8, blur: 12,
                    fontFamily: "Iosevka", fontSize: 14.5, gap: 6, radius: 9))
    }

    @Test func defaultLayoutIsParsed() throws {
        let config = try parse("[tiling]\ndefault_layout = \"master\"")

        #expect(config.defaultLayout == .master)
    }

    @Test(arguments: [0.3, 0.95])
    func glassOpacityAcceptsItsBounds(value: Double) throws {
        let config = try parse("[appearance]\nglass_opacity = \(value)")

        #expect(config.appearance.glassOpacity == value)
    }

    @Test(arguments: [0, 48])
    func blurAcceptsItsBounds(value: Int) throws {
        let config = try parse("[appearance]\nblur = \(value)")

        #expect(config.appearance.blur == Double(value))
    }

    // MARK: Errors

    @Test func syntaxErrorReportsLine() throws {
        let error = try error(parsingFixture: "syntax-error")

        #expect(error?.file == Self.file)
        #expect(error?.line == 3)
    }

    @Test func unknownKeyIsReportedWithLine() throws {
        let error = try error(parsingFixture: "unknown-key")

        #expect(error == ConfigError(file: Self.file, line: 4, key: "font_wieght", reason: "clave desconocida"))
    }

    @Test func unknownTableIsReportedWithLine() {
        let error = error(parsing: "[tiling]\n\n[colors]\nbackground = \"#000000\"")

        #expect(error == ConfigError(file: Self.file, line: 3, key: "colors", reason: "tabla desconocida"))
    }

    @Test func unknownTopLevelKeyIsReportedWithLine() {
        let error = error(parsing: "theme = \"obsidiana\"")

        #expect(error == ConfigError(file: Self.file, line: 1, key: "theme", reason: "clave desconocida"))
    }

    @Test func knownTableWithAValueIsReportedWithLine() {
        let error = error(parsing: "\nappearance = 3")

        #expect(error == ConfigError(file: Self.file, line: 2, key: "appearance", reason: "se esperaba una tabla"))
    }

    @Test func wrongTypeIsReportedWithLine() throws {
        let error = try error(parsingFixture: "wrong-type")

        #expect(error == ConfigError(file: Self.file, line: 3, key: "font_size", reason: "se esperaba un número"))
    }

    @Test func textValueWithWrongTypeIsReportedWithLine() {
        let error = error(parsing: "[appearance]\nfont_family = 13")

        #expect(error == ConfigError(file: Self.file, line: 2, key: "font_family", reason: "se esperaba un texto"))
    }

    @Test func unknownLayoutIsReportedWithLine() throws {
        let error = try error(parsingFixture: "unknown-layout")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "default_layout",
                    reason: "layout desconocido; se esperaba dwindle, columns o master"))
    }

    @Test(arguments: ["7aa2f7", "#7aa2f", "#7aa2f7ff", "#+7aa2f", "#7aa2fg"])
    func accentMustBeHexColor(value: String) {
        let error = error(parsing: "[appearance]\n\naccent = \"\(value)\"")

        #expect(
            error == ConfigError(file: Self.file, line: 3, key: "accent", reason: "se esperaba un color #rrggbb"))
    }

    @Test(arguments: [0.29, 0.96])
    func glassOpacityOutOfRangeIsRejected(value: Double) {
        let error = error(parsing: "[appearance]\nglass_opacity = \(value)")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "glass_opacity", reason: "se esperaba un número entre 0,3 y 0,95"))
    }

    @Test(arguments: [-1, 49])
    func blurOutOfRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nblur = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "blur", reason: "se esperaba un número entre 0 y 48"))
    }

    @Test(arguments: ["font_size", "gap", "radius", "glass_opacity", "blur"], ["nan", "inf", "-inf"])
    func nonFiniteNumberIsRejected(key: String, value: String) {
        let error = error(parsing: "[appearance]\n\(key) = \(value)")

        #expect(error?.key == key)
        #expect(error?.line == 2)
    }

    @Test func glassOpacityNaNIsRejected() {
        let error = error(parsing: "[appearance]\nglass_opacity = nan")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "glass_opacity", reason: "se esperaba un número entre 0,3 y 0,95"))
    }

    @Test func blurInfinityIsRejected() {
        let error = error(parsing: "[appearance]\nblur = inf")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "blur", reason: "se esperaba un número entre 0 y 48"))
    }

    @Test(arguments: [5, 73])
    func fontSizeOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nfont_size = \(value)")

        #expect(
            error
                == ConfigError(file: Self.file, line: 2, key: "font_size", reason: "se esperaba un número entre 6 y 72")
        )
    }

    @Test(arguments: [-1, 33])
    func gapOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\ngap = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "gap", reason: "se esperaba un número entre 0 y 32"))
    }

    @Test(arguments: [-1, 33])
    func radiusOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nradius = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "radius", reason: "se esperaba un número entre 0 y 32"))
    }

    @Test(arguments: [6, 72])
    func fontSizeAcceptsItsBounds(value: Int) throws {
        let config = try parse("[appearance]\nfont_size = \(value)")

        #expect(config.appearance.fontSize == Double(value))
    }

    @Test(arguments: [0, 32])
    func gapAndRadiusAcceptTheirBounds(value: Int) throws {
        let appearance = try parse("[appearance]\ngap = \(value)\nradius = \(value)").appearance

        #expect(appearance.gap == Double(value))
        #expect(appearance.radius == Double(value))
    }

    @Test func invalidEscapeInATextIsASyntaxError() {
        let error = error(parsing: "[appearance]\n\nfont_family = \"Jet\\qBrains\"")

        #expect(
            error == ConfigError(file: Self.file, line: 3, key: "font_family", reason: "sintaxis TOML no válida"))
    }

    @Test func emptyShellCommandIsRejected() {
        let error = error(parsing: "[shell]\ncommand = \"  \"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "command", reason: "se esperaba un comando o \"login\""))
    }

    // MARK: Keys

    @Test func shortcutReplacesTheStandardChord() throws {
        let config = try parse("[keys]\n\"cmd+j\" = \"palette.open\"")

        #expect(config.keys.chord(for: .paletteOpen) == KeyChord(key: "j", modifiers: [.command]))
    }

    @Test func unbindWithNone() throws {
        let config = try parseFixture("unbind")

        #expect(config.keys.command(for: try chord("cmd+w")) == nil)
        #expect(config.keys.chord(for: .paneClose) == nil)
    }

    @Test func plusKeyIsWrittenPlus() throws {
        let config = try parse("[keys]\n\"cmd+plus\" = \"panes.equalize\"")

        #expect(config.keys.chord(for: .panesEqualize) == KeyChord(key: "plus", modifiers: [.command]))
    }

    @Test func optionOnlyShortcutIsRejectedWithLine() throws {
        let error = try error(parsingFixture: "option-only")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "opt+k", reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir"))
    }

    @Test func firstOptionOnlyChordInFileOrderIsReported() {
        let error = error(parsing: "[keys]\n\"opt+z\" = \"pane.new\"\n\"opt+a\" = \"pane.close\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "opt+z", reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir"))
    }

    @Test func unknownCommandIsReportedWithLine() {
        let error = error(parsing: "[keys]\n\"cmd+k\" = \"palette.open\"\n\"cmd+j\" = \"pane.explode\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "cmd+j",
                    reason: "comando desconocido; se esperaba un id de comando o \"none\""))
    }

    @Test func commandWithWrongTypeIsReportedWithLine() {
        let error = error(parsing: "[keys]\n\"cmd+j\" = 3")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "cmd+j", reason: "se esperaba un id de comando o \"none\""))
    }

    @Test func duplicateChordIsReportedOnTheSecondOccurrence() {
        let error = error(parsing: "[keys]\n\"cmd+j\" = \"palette.open\"\n\"command+j\" = \"pane.new\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "command+j", reason: "atajo repetido; ya aparece como cmd+j"))
    }

    @Test(arguments: [
        ("k", "falta un modificador (⌘, ⌃ o ⌥)"),
        ("cmd+cmd+k", "modificador repetido: cmd"),
        ("hyper+k", "modificador desconocido: hyper"),
        ("cmd+space", "tecla desconocida: space"),
        ("cmd++", "falta la tecla; el + se escribe plus"),
    ])
    func chordErrorIsTranslatedWithLine(chord: String, reason: String) {
        let error = error(parsing: "[keys]\n\n\"\(chord)\" = \"palette.open\"")

        #expect(error == ConfigError(file: Self.file, line: 3, key: chord, reason: reason))
    }
}
