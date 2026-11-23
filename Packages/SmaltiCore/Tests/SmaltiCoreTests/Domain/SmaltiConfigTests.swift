import SmaltiCore
import Testing

@Suite("SmaltiConfig")
struct SmaltiConfigTests {
    @Test func defaultsMatchObsidianTokens() throws {
        let config = SmaltiConfig.defaults

        #expect(config.appearance.accent == (try RGBAColor(hex: "#7aa2f7")))
        #expect(config.appearance.glassOpacity == 0.62)
        #expect(config.appearance.blur == 28)
        #expect(config.appearance.fontFamily == "JetBrains Mono")
        #expect(config.appearance.fontSize == 13)
        #expect(config.appearance.gap == 8)
        #expect(config.appearance.radius == 11)
        #expect(config.defaultLayout == .dwindle)
        #expect(config.shell == .loginShell)
        #expect(config.keys == Keymap.standard)
    }

    @Test func launchShellOverrideWinsOverConfiguredShell() {
        var config = SmaltiConfig.defaults
        config.shell = .custom("/opt/homebrew/bin/fish")

        let resolved = config.withShell(overriddenBy: .custom("/bin/zsh -f"))

        #expect(resolved.shell == .custom("/bin/zsh -f"))
    }

    @Test func missingLaunchOverrideKeepsConfiguredShell() {
        var config = SmaltiConfig.defaults
        config.shell = .custom("/opt/homebrew/bin/fish")

        #expect(config.withShell(overriddenBy: nil) == config)
    }

    @Test func applyingDefaultsLeavesObsidianUnchanged() {
        #expect(Theme.obsidian.applying(.obsidian) == Theme.obsidian)
    }

    @Test func themeApplyingAppearanceChangesAccentAndGap() throws {
        let accent = try RGBAColor(hex: "#ff0000")
        var appearance = AppearanceSettings.obsidian
        appearance.accent = accent
        appearance.gap = 4

        let theme = Theme.obsidian.applying(appearance)

        #expect(theme.accent == accent)
        #expect(theme.panel.gap == 4)
        #expect(theme.terminal.cursor == accent)
        #expect(theme.focus.ring == RGBAColor(red: 255, green: 0, blue: 0, alpha: 0x80 / 255))
        #expect(theme.focus.glow == RGBAColor(red: 255, green: 0, blue: 0, alpha: 0x22 / 255))
        #expect(theme.palette.selection == RGBAColor(red: 255, green: 0, blue: 0, alpha: 0x26 / 255))
    }

    @Test func themeApplyingAppearanceChangesGlassBlurFontAndRadius() {
        var appearance = AppearanceSettings.obsidian
        appearance.glassOpacity = 0.4
        appearance.blur = 10
        appearance.fontFamily = "Menlo"
        appearance.fontSize = 15
        appearance.radius = 6

        let theme = Theme.obsidian.applying(appearance)

        #expect(theme.window.background.alpha == 0.4)
        #expect(theme.window.background.red == Theme.obsidian.window.background.red)
        #expect(theme.window.blurRadius == 10)
        #expect(theme.terminal.fontFamily == "Menlo")
        #expect(theme.terminal.fontSize == 15)
        #expect(theme.panel.cornerRadius == 6)
    }

    @Test func configErrorSummaryNamesFileLineAndKey() {
        let error = ConfigError(file: "config.toml", line: 12, key: "font_size", reason: "se esperaba un número")

        #expect(error.summary == "config.toml:12 · font_size: se esperaba un número")
    }

    @Test func configErrorSummaryOmitsMissingParts() {
        #expect(
            ConfigError(file: "config.toml", line: nil, key: nil, reason: "ilegible").summary
                == "config.toml · ilegible")
        #expect(ConfigError(file: "", line: nil, key: "⌥C", reason: "reservado").summary == "⌥C: reservado")
    }

    @Test(arguments: [
        "JetBrains Mono", "a", String(repeating: "a", count: AppearanceSettings.maximumFontFamilyLength), "Fira Código",
    ])
    func fontFamilyIsValid(_ name: String) {
        #expect(AppearanceSettings.isValidFontFamily(name))
    }

    @Test(arguments: [
        "", String(repeating: "a", count: AppearanceSettings.maximumFontFamilyLength + 1), "Jet\"Brains",
        "Jet\\Brains", "Jet\nBrains", "Jet\rBrains", "Jet\tBrains", "Jet\u{7}Brains", "Jet\u{7F}Brains",
    ])
    func fontFamilyIsInvalid(_ name: String) {
        #expect(!AppearanceSettings.isValidFontFamily(name))
    }

    @Test func maximumFontFamilyLengthIsOneHundred() {
        #expect(AppearanceSettings.maximumFontFamilyLength == 100)
    }
}
