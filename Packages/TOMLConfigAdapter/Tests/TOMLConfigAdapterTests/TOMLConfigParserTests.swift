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

    /// The fixture writes every key, `accent` included: since F5 a written accent is the user's choice, so the result
    /// is the defaults with Obsidiana's accent chosen explicitly.
    @Test func fullDefaultFileRoundTripsToDefaults() throws {
        let config = try parseFixture("defaults")

        #expect(config == .defaultsWithExplicitAccent)
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

        #expect(error == ConfigError(file: Self.file, line: 4, key: "font_wieght", problem: .unknownKey))
    }

    @Test func unknownTableIsReportedWithLine() {
        let error = error(parsing: "[tiling]\n\n[colors]\nbackground = \"#000000\"")

        #expect(error == ConfigError(file: Self.file, line: 3, key: "colors", problem: .unknownTable))
    }

    @Test func unknownTopLevelKeyIsReportedWithLine() {
        let error = error(parsing: "theme = \"obsidiana\"")

        #expect(error == ConfigError(file: Self.file, line: 1, key: "theme", problem: .unknownKey))
    }

    @Test func knownTableWithAValueIsReportedWithLine() {
        let error = error(parsing: "\nappearance = 3")

        #expect(error == ConfigError(file: Self.file, line: 2, key: "appearance", problem: .expectedTable))
    }

    @Test func wrongTypeIsReportedWithLine() throws {
        let error = try error(parsingFixture: "wrong-type")

        #expect(error == ConfigError(file: Self.file, line: 3, key: "font_size", problem: .expectedNumber))
    }

    @Test func textValueWithWrongTypeIsReportedWithLine() {
        let error = error(parsing: "[appearance]\nfont_family = 13")

        #expect(error == ConfigError(file: Self.file, line: 2, key: "font_family", problem: .expectedText))
    }

    /// Values that could break or inject lines into the generated engine config, as TOML source.
    @Test(arguments: [
        #""""#,
        "\"\(String(repeating: "a", count: 101))\"",
        #""Jet\"Brains""#,
        #""Jet\\Brains""#,
        #""Jet\nBrains""#,
        #""Jet\tBrains""#,
        #""Jet\u0007Brains""#,
        #""Jet\u007FBrains""#,
    ])
    func unsafeFontFamilyIsRejected(_ value: String) {
        let error = error(parsing: "[appearance]\nfont_family = \(value)")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "font_family",
                    problem: .expectedFontName(maximumLength: 100)))
    }

    @Test func fontFamilyOfOneHundredCharactersIsAccepted() throws {
        let name = String(repeating: "a", count: 100)

        let config = try parse("[appearance]\nfont_family = \"\(name)\"")

        #expect(config.appearance.fontFamily == name)
    }

    @Test func unknownLayoutIsReportedWithLine() throws {
        let error = try error(parsingFixture: "unknown-layout")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "default_layout",
                    problem: .unknownLayout(["dwindle", "columns", "master"])))
    }

    @Test(arguments: ["7aa2f7", "#7aa2f", "#7aa2f7ff", "#+7aa2f", "#7aa2fg"])
    func accentMustBeHexColor(value: String) {
        let error = error(parsing: "[appearance]\n\naccent = \"\(value)\"")

        #expect(
            error == ConfigError(file: Self.file, line: 3, key: "accent", problem: .expectedColor))
    }

    @Test(arguments: [0.29, 0.96])
    func glassOpacityOutOfRangeIsRejected(value: Double) {
        let error = error(parsing: "[appearance]\nglass_opacity = \(value)")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "glass_opacity", problem: .expectedNumberBetween(0.3, 0.95)))
    }

    @Test(arguments: [-1, 49])
    func blurOutOfRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nblur = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "blur", problem: .expectedNumberBetween(0, 48)))
    }

    @Test(arguments: ["font_size", "gap", "radius", "glass_opacity", "blur"], ["nan", "inf", "-inf"])
    func nonFiniteNumberIsRejected(key: String, value: String) {
        let ranges = [
            "font_size": "6 y 72", "gap": "0 y 32", "radius": "0 y 32", "glass_opacity": "0,3 y 0,95",
            "blur": "0 y 48",
        ]

        let error = error(parsing: "[appearance]\n\(key) = \(value)")

        #expect(error?.key == key)
        #expect(error?.line == 2)
        #expect(error?.reason == ranges[key].map { "se esperaba un número entre \($0)" })
    }

    @Test func glassOpacityNaNIsRejected() {
        let error = error(parsing: "[appearance]\nglass_opacity = nan")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "glass_opacity", problem: .expectedNumberBetween(0.3, 0.95)))
    }

    @Test func blurInfinityIsRejected() {
        let error = error(parsing: "[appearance]\nblur = inf")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "blur", problem: .expectedNumberBetween(0, 48)))
    }

    @Test(arguments: [5, 73])
    func fontSizeOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nfont_size = \(value)")

        #expect(
            error
                == ConfigError(file: Self.file, line: 2, key: "font_size", problem: .expectedNumberBetween(6, 72))
        )
    }

    @Test(arguments: [-1, 33])
    func gapOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\ngap = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "gap", problem: .expectedNumberBetween(0, 32)))
    }

    @Test(arguments: [-1, 33])
    func radiusOutsideRangeIsRejected(value: Int) {
        let error = error(parsing: "[appearance]\nradius = \(value)")

        #expect(
            error == ConfigError(file: Self.file, line: 2, key: "radius", problem: .expectedNumberBetween(0, 32)))
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
            error == ConfigError(file: Self.file, line: 3, key: "font_family", problem: .syntax))
    }

    @Test func emptyShellCommandIsRejected() {
        let error = error(parsing: "[shell]\ncommand = \"  \"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "command", problem: .expectedShellCommand))
    }

    // MARK: Keys

    @Test func shortcutReplacesTheStandardChord() throws {
        let config = try parse("[keys]\n\"cmd+j\" = \"palette.open\"")

        #expect(config.keys.chords(for: .paletteOpen) == [try chord("cmd+j")])
    }

    /// F4.5: two lines for one command give it two chords; the first one written is its primary.
    @Test func twoLinesGiveTwoChordsInFileOrder() throws {
        let config = try parse("[keys]\n\"cmd+m\" = \"palette.open\"\n\"cmd+j\" = \"palette.open\"")

        #expect(config.keys.chords(for: .paletteOpen) == [try chord("cmd+m"), try chord("cmd+j")])
    }

    @Test func shortcutMovesWithNoneOnTheStandardChord() throws {
        let config = try parse("[keys]\n\"cmd+j\" = \"palette.open\"\n\"cmd+k\" = \"none\"")

        #expect(config.keys.chords(for: .paletteOpen) == [try chord("cmd+j")])
    }

    @Test func unbindWithNone() throws {
        let config = try parseFixture("unbind")

        #expect(config.keys.command(for: try chord("cmd+w")) == nil)
        #expect(config.keys.chord(for: .paneClose) == nil)
    }

    @Test func plusKeyIsWrittenPlus() throws {
        let config = try parse("[keys]\n\"cmd+plus\" = \"panes.equalize\"")

        #expect(config.keys.command(for: KeyChord(key: "plus", modifiers: [.command])) == .panesEqualize)
    }

    @Test func optionOnlyShortcutIsRejectedWithLine() throws {
        let error = try error(parsingFixture: "option-only")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "opt+k", problem: .reservedOption))
    }

    @Test func firstOptionOnlyChordInFileOrderIsReported() {
        let error = error(parsing: "[keys]\n\"opt+z\" = \"pane.new\"\n\"opt+a\" = \"pane.close\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "opt+z", problem: .reservedOption))
    }

    @Test func unknownCommandIsReportedWithLine() {
        let error = error(parsing: "[keys]\n\"cmd+k\" = \"palette.open\"\n\"cmd+j\" = \"pane.explode\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "cmd+j",
                    problem: .unknownCommand))
    }

    @Test func commandWithWrongTypeIsReportedWithLine() {
        let error = error(parsing: "[keys]\n\"cmd+j\" = 3")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 2, key: "cmd+j", problem: .expectedCommandID))
    }

    @Test func duplicateChordIsReportedOnTheSecondOccurrence() {
        let error = error(parsing: "[keys]\n\"cmd+j\" = \"palette.open\"\n\"command+j\" = \"pane.new\"")

        #expect(
            error
                == ConfigError(
                    file: Self.file, line: 3, key: "command+j", problem: .repeatedShortcut(first: "cmd+j")))
    }

    @Test(arguments: [
        ("k", "falta un modificador (⌘, ⌃ o ⌥)"),
        ("cmd+cmd+k", "modificador repetido: cmd"),
        ("hyper+k", "modificador desconocido: hyper"),
        ("cmd+space", "tecla desconocida: space"),
        ("cmd++", "falta la tecla; el + se escribe plus"),
        ("shift+cmd+1", "⇧ no cuenta con números ni símbolos: escribe el carácter (cmd+? en vez de shift+cmd+/)"),
    ])
    func chordErrorIsTranslatedWithLine(chord: String, reason: String) {
        let error = error(parsing: "[keys]\n\n\"\(chord)\" = \"palette.open\"")

        #expect(error?.file == Self.file)
        #expect(error?.line == 3)
        #expect(error?.key == chord)
        #expect(error?.reason == reason)
    }
}

@Suite("TOML · F4.5")
struct TOMLF45Tests {
    private func parse(_ text: String) throws -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: "config.toml")
    }

    /// C12: the template ⌘, writes, with every value uncommented, reads as the defaults.
    @Test func templateUncommentedEqualsDefaults() throws {
        let text = ConfigTemplate.uncommented(
            ConfigTemplate.text(defaults: .defaults, texts: ConfigTexts.spanish.template))

        #expect(try parse(text) == .defaultsWithExplicitAccent)
    }

    @Test func templateAsWrittenReadsAsDefaults() throws {
        #expect(try parse(ConfigTemplate.text(defaults: .defaults, texts: ConfigTexts.spanish.template)) == .defaults)
    }

    @Test func windowConfirmCloseParses() throws {
        #expect(try parse("[window]\nconfirm_close = false").window.confirmClose == false)
    }

    @Test func windowConfirmCloseRejectsNonBool() {
        #expect(throws: ConfigError.self) { try parse("[window]\nconfirm_close = \"no\"") }
    }

    @Test func windowRejectsUnknownKeys() {
        #expect(throws: ConfigError.self) { try parse("[window]\nconfirm = true") }
    }
}

@Suite("TOML · F4.5 template examples")
struct TOMLTemplateExampleTests {
    /// The commented observatory example, uncommented by hand, is a valid table.
    @Test func observatoryExampleParses() throws {
        let lines = ConfigTemplate.text(defaults: .defaults, texts: ConfigTexts.spanish.template).split(separator: "\n")
        let example = lines.drop { !$0.hasPrefix("# [observatory.models.") }.prefix { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)) }.joined(separator: "\n")

        #expect(!example.isEmpty)
        #expect(throws: Never.self) { try TOMLConfigParser.parse(example, file: "config.toml") }
    }
}

extension SmaltiConfig {
    /// `SmaltiConfig.defaults` with `accent` written out, as a file that lists every key reads.
    fileprivate static var defaultsWithExplicitAccent: SmaltiConfig {
        var config = SmaltiConfig.defaults
        config.appearance.accent = Theme.obsidian.accent
        return config
    }
}

/// F7.7 `[keyboard] option_as_meta`.
@Suite("Keyboard section")
struct KeyboardSectionTests {
    @Test func optionAsMetaIsRead() throws {
        let config = try TOMLConfigParser.parse("[keyboard]\noption_as_meta = \"left\"\n", file: "config.toml")

        #expect(config.optionAsMeta == .left)
    }

    @Test func missingSectionKeepsAuto() throws {
        #expect(try TOMLConfigParser.parse("", file: "config.toml").optionAsMeta == .auto)
    }

    @Test func invalidValueNamesTheChoices() {
        #expect(
            throws: ConfigError(
                file: "config.toml", line: 2, key: "option_as_meta",
                problem: .expectedOneOf(["auto", "never", "left", "right", "always"]))
        ) {
            try TOMLConfigParser.parse("[keyboard]\noption_as_meta = \"yes\"\n", file: "config.toml")
        }
    }

    @Test func unknownKeyIsRejected() {
        #expect(throws: ConfigError(file: "config.toml", line: 2, key: "meta", problem: .unknownKey)) {
            try TOMLConfigParser.parse("[keyboard]\nmeta = true\n", file: "config.toml")
        }
    }
}
