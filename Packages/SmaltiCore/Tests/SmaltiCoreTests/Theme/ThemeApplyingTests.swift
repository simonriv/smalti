import Foundation
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

    @Test func appliedThemeKeepsItsWindowShadow() {
        let applied = ThemeCatalog.apply(settings { $0.theme = .niebla })

        #expect(applied.theme.window.shadow == ThemeCatalog.theme(.niebla).window.shadow)
    }

    @Test func protectionRaisesPanelTo66InObsidian() {
        let applied = ThemeCatalog.apply(settings())

        #expect(applied.theme.panel.background.alpha == 0.66)
        #expect(applied.opacities.panel == 0.66)
    }

    @Test func nieblaProtectsAgainstBlackDesktop() {
        let applied = ThemeCatalog.apply(settings { $0.theme = .niebla })

        #expect(applied.opacities.panel == 0.83)
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

    @Test func overrideAppliesToItsTheme() throws {
        let overrides = try ANSIOverrides([2: hex("#00ff00")])
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: overrides] })

        #expect(applied.theme.terminal.palette[2] == hex("#00ff00"))
    }

    @Test func overrideOfOtherThemeIsIgnored() throws {
        let overrides = try ANSIOverrides([1: hex("#ff0000")])
        let applied = ThemeCatalog.apply(
            settings {
                $0.protectLegibility = false
                $0.ansiOverrides = [.bosque: overrides]
            })

        #expect(applied.theme.terminal.palette == Theme.obsidian.terminal.palette)
    }

    @Test func unreachableOverrideIsAdjustedAndCounted() throws {
        let overrides = try ANSIOverrides([1: hex("#15161e")])
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: overrides] })

        #expect(applied.adjustedColorCount == 1)
        #expect(ContrastRatio.between(applied.theme.terminal.palette[1], panelGround(applied)) >= 4.5)
    }

    @Test func unreachableOverrideDoesNotForceOpaquePanel() throws {
        let overrides = try ANSIOverrides([1: hex("#15161e")])
        let applied = ThemeCatalog.apply(settings { $0.ansiOverrides = [.obsidiana: overrides] })

        #expect(applied.opacities.panel == 0.66)
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

/// C2 (block 1 review, I1 and I4): every theme, glass from 30 to 95 %, checked with exact (unrounded) blending as Core
/// Animation does, so 8-bit rounding in the search can never leave a color at 4.49 on screen.
@Suite("Proteger legibilidad · C2")
struct LegibilityC2Tests {
    private struct Exact {
        var red, green, blue: Double

        init(_ color: RGBAColor) {
            red = Double(color.red)
            green = Double(color.green)
            blue = Double(color.blue)
        }

        func under(_ top: RGBAColor) -> Exact {
            var result = self
            result.red = Double(top.red) * top.alpha + red * (1 - top.alpha)
            result.green = Double(top.green) * top.alpha + green * (1 - top.alpha)
            result.blue = Double(top.blue) * top.alpha + blue * (1 - top.alpha)
            return result
        }

        private static func linear(_ channel: Double) -> Double {
            let value = channel / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        var luminance: Double {
            0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
        }

        func contrast(with color: RGBAColor) -> Double {
            let other = Exact(color).luminance
            return (max(luminance, other) + 0.05) / (min(luminance, other) + 0.05)
        }
    }

    private static let opacities = [0.30, 0.50, 0.75, 0.85, 0.90, 0.95]

    private func applied(_ id: ThemeID, glass: Double) -> AppliedTheme {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = id
        appearance.glassOpacity = glass
        return ThemeCatalog.apply(appearance)
    }

    private func failing(_ colors: [RGBAColor], on ground: Exact) -> [String] {
        colors.filter { ground.contrast(with: $0) < LegibilityGuard.minimumContrast }.map(\.hexString)
    }

    @Test(arguments: ThemeID.allCases, opacities)
    func panelTextStaysAt4_5(_ id: ThemeID, glass: Double) {
        let applied = applied(id, glass: glass)
        let theme = applied.theme
        let ground = Exact(id.worstBackdrop.color).under(theme.window.background).under(theme.panel.background)
        let colors =
            [theme.text.primary, theme.text.secondary, theme.text.ghostText]
            + theme.terminal.palette.enumerated().filter { !id.backgroundIndices.contains($0.offset) }.map(\.element)

        #expect(failing(colors, on: ground).isEmpty, "\(id) \(glass): \(failing(colors, on: ground))")
    }

    @Test(arguments: ThemeID.allCases, opacities)
    func chromeTextStaysAt4_5(_ id: ThemeID, glass: Double) {
        let theme = applied(id, glass: glass).theme
        let chrome = theme.window.background.withAlpha(applied(id, glass: glass).opacities.chrome)
        let ground = Exact(id.worstBackdrop.color).under(theme.window.background).under(chrome)
        let colors = [theme.text.primary, theme.text.title, theme.text.secondary]

        #expect(failing(colors, on: ground).isEmpty, "\(id) \(glass): \(failing(colors, on: ground))")
    }

    @Test(arguments: ThemeID.allCases, opacities)
    func overlayTextStaysAt4_5(_ id: ThemeID, glass: Double) {
        let theme = applied(id, glass: glass).theme
        let ground = Exact(id.worstBackdrop.color).under(theme.window.background).under(theme.palette.background)
        let colors = [theme.text.primary, theme.text.title, theme.text.secondary]

        #expect(failing(colors, on: ground).isEmpty, "\(id) \(glass): \(failing(colors, on: ground))")
    }

    @Test(arguments: ThemeID.allCases)
    func observatoryCardFollowsProtectedPanel(_ id: ThemeID) {
        let theme = applied(id, glass: 0.62).theme

        #expect(theme.observatory.cardBackground == theme.panel.background)
    }
}

/// Block 1 review (M2, M5): the user's higher glass is kept as is, and text on accent-filled buttons follows the
/// effective accent.
@Suite("ThemeCatalog.apply · review")
struct ThemeApplyingReviewTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    @Test func protectionKeepsDesignPanelWhenGlassIsAlmostOpaque() {
        var appearance = AppearanceSettings.obsidian
        appearance.glassOpacity = 0.95

        let applied = ThemeCatalog.apply(appearance)

        #expect(applied.theme.panel.background.alpha == 0.34)
        #expect(applied.theme.window.background.alpha == 0.95)
    }

    @Test func lightAccentOnNieblaGetsDarkButtonText() {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = .niebla
        appearance.accent = hex("#ffe066")

        let theme = ThemeCatalog.apply(appearance).theme

        #expect(theme.resume.primaryButtonText == theme.text.primary)
    }

    @Test(arguments: ThemeID.allCases)
    func themeAccentKeepsDesignButtonText(_ id: ThemeID) {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = id

        let theme = ThemeCatalog.apply(appearance).theme

        #expect(theme.resume.primaryButtonText == ThemeCatalog.theme(id).resume.primaryButtonText)
    }
}
