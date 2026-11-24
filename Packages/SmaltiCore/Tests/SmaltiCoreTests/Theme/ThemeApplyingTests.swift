import SmaltiCore
import Testing

/// Spec F5: the theme chosen in `AppearanceSettings`, with its ANSI edits, accent and "Proteger legibilidad".
@Suite("ThemeCatalog.apply")
struct ThemeApplyingTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    private func settings(_ change: (inout AppearanceSettings) -> Void = { _ in }) -> AppearanceSettings {
        var appearance = AppearanceSettings.obsidian
        change(&appearance)
        return appearance
    }

    /// What text on a panel sits on, over the worst desktop.
    private func panelGround(_ applied: AppliedTheme, backdrop: Backdrop = .white) -> RGBAColor {
        backdrop.color.underneath(applied.theme.window.background).underneath(applied.theme.panel.background)
    }

    @Test func defaultsProtectLegibility() {
        #expect(AppearanceSettings.obsidian.protectLegibility)
        #expect(AppearanceSettings.obsidian.theme == .obsidiana)
        #expect(AppearanceSettings.obsidian.accent == nil)
    }

    @Test func protectionRaisesPanelTo65InObsidian() {
        let applied = ThemeCatalog.apply(settings())

        #expect(applied.theme.panel.background.alpha == 0.65)
        #expect(applied.opacities.panel == 0.65)
    }

    @Test func nieblaProtectsAgainstBlackDesktop() {
        let applied = ThemeCatalog.apply(settings { $0.theme = .niebla })

        #expect(applied.opacities.panel == 0.82)
    }

    @Test func protectionNeverLowersTheGlass() {
        let applied = ThemeCatalog.apply(settings { $0.glassOpacity = 0.95 })

        #expect(applied.theme.window.background.alpha == 0.95)
        #expect(applied.theme.panel.background.alpha >= 0.34)
    }

    @Test func withoutProtectionThemeIsExact() {
        let applied = ThemeCatalog.apply(settings { $0.protectLegibility = false })

        #expect(applied.theme.panel.background.alpha == 0.34)
        #expect(applied.theme.text.ghostText == hex("#5f6672"))
        #expect(applied.theme.terminal.palette == Theme.obsidian.terminal.palette)
        #expect(applied.opacities.chrome == 0)
        #expect(applied.adjustedColorCount == 0)
    }

    @Test func lowestOpacityStillProtected() {
        let applied = ThemeCatalog.apply(settings { $0.glassOpacity = 0.30 })
        let ground = panelGround(applied)
        let palette = applied.theme.terminal.palette
        let protected =
            [applied.theme.text.primary, applied.theme.text.secondary, applied.theme.text.ghostText]
            + palette.enumerated().filter { ![0, 8].contains($0.offset) }.map(\.element)

        let failing = protected.filter { ContrastRatio.between($0, ground) < 4.5 }

        #expect(failing.isEmpty, "\(failing.map(\.hexString))")
    }

    @Test func ghostIsLegibleWithProtection() {
        let applied = ThemeCatalog.apply(settings())

        #expect(ContrastRatio.between(applied.theme.text.ghostText, panelGround(applied)) >= 4.5)
        #expect(applied.theme.text.ghostText != hex("#5f6672"))
    }

    @Test func accentOverrideWinsOverTheme() {
        let red = hex("#ff0000")

        let applied = ThemeCatalog.apply(settings { $0.accent = red })

        #expect(applied.theme.accent == red)
        #expect(applied.theme.terminal.cursor == red)
    }

    @Test func themeAccentWhenNoOverride() {
        let applied = ThemeCatalog.apply(settings { $0.theme = .niebla })

        #expect(applied.theme.accent == hex("#3b5bdb"))
    }

    @Test func overrideAppliesToItsTheme() {
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: [2: hex("#00ff00")]] })

        #expect(applied.theme.terminal.palette[2] == hex("#00ff00"))
    }

    @Test func overrideOfOtherThemeIsIgnored() {
        let applied = ThemeCatalog.apply(
            settings {
                $0.protectLegibility = false
                $0.ansiOverrides = [.bosque: [1: hex("#ff0000")]]
            })

        #expect(applied.theme.terminal.palette == Theme.obsidian.terminal.palette)
    }

    @Test func unreachableOverrideIsAdjustedAndCounted() {
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: [1: hex("#15161e")]] })

        #expect(applied.adjustedColorCount == 1)
        #expect(ContrastRatio.between(applied.theme.terminal.palette[1], panelGround(applied)) >= 4.5)
    }

    @Test func unreachableOverrideDoesNotForceOpaquePanel() {
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: [1: hex("#15161e")]] })

        #expect(applied.opacities.panel == 0.65)
    }

    @Test func backgroundPairIsNeverAdjusted() {
        let applied = ThemeCatalog.apply(settings())

        #expect(applied.theme.terminal.palette[0] == hex("#15161e"))
        #expect(applied.theme.terminal.palette[8] == hex("#414868"))
    }

    @Test func chromeOpacityProtectsSecondary() {
        let applied = ThemeCatalog.apply(settings())
        let glass = applied.theme.window.background
        let ground = Backdrop.white.color.underneath(glass).underneath(glass.withAlpha(applied.opacities.chrome))

        #expect(ContrastRatio.between(applied.theme.text.secondary, ground) >= 4.5)
        #expect(applied.opacities.chrome > 0)
    }

    @Test func overlayKeepsAtLeastItsDesignOpacity() {
        let applied = ThemeCatalog.apply(settings())
        let overlay = applied.theme.palette.background
        let ground = Backdrop.white.color.underneath(applied.theme.window.background).underneath(overlay)

        #expect(overlay.alpha >= 0.82)
        #expect(applied.opacities.overlay == overlay.alpha)
        #expect(ContrastRatio.between(applied.theme.text.secondary, ground) >= 4.5)
    }

    @Test func userSizesStillApply() {
        let applied = ThemeCatalog.apply(
            settings {
                $0.gap = 4
                $0.radius = 6
                $0.fontSize = 15
                $0.blur = 0
            })

        #expect(applied.theme.panel.gap == 4)
        #expect(applied.theme.panel.cornerRadius == 6)
        #expect(applied.theme.terminal.fontSize == 15)
        #expect(applied.theme.window.blurRadius == 0)
    }
}
