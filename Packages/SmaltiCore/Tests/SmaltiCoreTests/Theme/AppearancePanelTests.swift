import Foundation
import SmaltiCore
import Testing

/// Spec F5, panel Apariencia (`Apariencia.dc.html`): texts, theme cards and the edits its controls make.
@Suite("Appearance panel")
struct AppearancePanelTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    private var document: AppearanceDocument { AppearanceDocument(config: .defaults) }

    @Test func opacityShowsTheChosenValue() {
        #expect(AppearanceTexts.opacity(chosen: 0.62, underText: 0.62, copy: .spanish) == "62%")
    }

    @Test func opacitySaysWhenProtectionRaisesItUnderText() {
        #expect(AppearanceTexts.opacity(chosen: 0.62, underText: 0.66, copy: .spanish) == "62% · 66% bajo el texto")
    }

    @Test func blurIsInPixels() {
        #expect(AppearanceTexts.blur(28) == "28 px")
    }

    @Test func noAdjustedColorsSaysNothing() {
        #expect(AppearanceTexts.adjusted(0, copy: .spanish) == nil)
    }

    @Test func oneAdjustedColorIsSingular() {
        #expect(AppearanceTexts.adjusted(1, copy: .spanish) == "Ajustados por legibilidad: 1 color")
    }

    @Test func severalAdjustedColors() {
        #expect(AppearanceTexts.adjusted(3, copy: .spanish) == "Ajustados por legibilidad: 3 colores")
    }

    @Test func homeFileIsShortenedLikeTheBoard() {
        let text = AppearanceTexts.savedIn(
            path: "/Users/simon/.config/smalti/theme.toml", home: "/Users/simon", copy: .spanish)

        #expect(text == "se guarda en ~/.config/…/theme.toml")
    }

    @Test func shortPathIsShownWhole() {
        #expect(
            AppearanceTexts.savedIn(path: "/tmp/theme.toml", home: "/Users/simon", copy: .spanish)
                == "se guarda en /tmp/theme.toml")
    }

    @Test func pathOutsideTheHomeKeepsItsFirstFolder() {
        let text = AppearanceTexts.savedIn(
            path: "/var/folders/x1/T/run/theme.toml", home: "/Users/simon", copy: .spanish)

        #expect(text == "se guarda en /var/…/theme.toml")
    }

    @Test func fontShowsFamilyAndSize() {
        #expect(AppearanceTexts.font(family: "JetBrains Mono", size: 13) == "JetBrains Mono 13")
    }

    @Test func obsidianCardUsesTheBoardSwatch() {
        let swatch = ThemeID.obsidiana.swatch

        #expect(
            swatch
                == ThemeSwatch(
                    background: hex("#12141b"), accent: hex("#7aa2f7"), text: hex("#c3c7cf"), green: hex("#9ece6a")))
    }

    @Test func nieblaCardIsLight() {
        #expect(ThemeID.niebla.swatch.background == hex("#eef0f4"))
        #expect(ThemeID.niebla.cardNote == "· claro")
    }

    @Test func darkCardsHaveNoNote() {
        #expect(ThemeID.allCases.filter { $0.cardNote != nil } == [.niebla])
    }

    @Test func nextThemeFollowsTheBoardOrderAndWraps() {
        #expect(ThemeID.allCases.map(\.next) == [.niebla, .ambarNocturno, .bosque, .obsidiana])
    }

    @Test func ansiEditGoesToTheCurrentThemeOnly() throws {
        var edited = document
        edited.appearance.theme = .bosque

        try edited.setANSI(1, to: hex("#ff6b6b"))

        #expect(edited.appearance.ansiOverrides[.bosque]?.colors == [1: hex("#ff6b6b")])
        #expect(edited.appearance.ansiOverrides[.obsidiana] == nil)
    }

    @Test func ansiIndexOutsideTheRangeIsRejected() {
        var edited = document

        #expect(throws: ColorError.self) { try edited.setANSI(16, to: hex("#ffffff")) }
    }

    @Test func resetDropsOnlyTheCurrentThemeEdits() throws {
        var edited = document
        try edited.setANSI(1, to: hex("#ff0000"))
        edited.appearance.theme = .bosque
        try edited.setANSI(2, to: hex("#00ff00"))

        edited.resetANSI()

        #expect(edited.appearance.ansiOverrides[.bosque] == nil)
        #expect(edited.appearance.ansiOverrides[.obsidiana]?.colors == [1: hex("#ff0000")])
    }

    @Test func sliderRangesAreTheSpecs() {
        #expect(AppearanceSettings.glassOpacityRange == 0.3...0.95)
        #expect(AppearanceSettings.blurRange == 0...48)
        #expect(AppearanceSettings.fontSizeRange == 6...72)
        #expect(AppearanceSettings.gapRange == 0...32)
        #expect(AppearanceSettings.radiusRange == 0...32)
    }

    @Test func stepsAreClampedToTheRange() {
        #expect(AppearanceSettings.clamped(0.96, to: AppearanceSettings.glassOpacityRange) == 0.95)
        #expect(AppearanceSettings.clamped(-1, to: AppearanceSettings.blurRange) == 0)
        #expect(AppearanceSettings.clamped(20, to: AppearanceSettings.gapRange) == 20)
    }
}

@Suite("Appearance panel tokens")
struct AppearancePanelTokensTests {
    @Test func sizesAreTheBoards() {
        let tokens = Theme.obsidian.appearancePanel

        #expect(tokens.width == 440)
        #expect(tokens.paddingVertical == 22)
        #expect(tokens.paddingHorizontal == 24)
        #expect(tokens.sectionGap == 22)
        #expect(tokens.swatchSize == 22)
        #expect(tokens.segmentHeight == 30)
    }

    /// Block 4 review (M3): the board's inner gaps and borders, no loose numbers in the views.
    @Test func innerGapsAreTheBoards() {
        let tokens = Theme.obsidian.appearancePanel

        #expect(tokens.cardInnerGap == 7)
        #expect(tokens.noteGap == 2)
        #expect(tokens.sliderGap == 6)
        #expect(tokens.footerGap == 4)
        #expect(tokens.stepperGap == 4)
        #expect(tokens.segmentLabelInset == 4)
        #expect(tokens.segmentContainerBorderWidth == 1)
        #expect(tokens.borderWidth == 1)
    }

    @Test func colorsFollowTheTheme() {
        let theme = ThemeCatalog.theme(.niebla)
        let tokens = theme.appearancePanel

        #expect(tokens.title == theme.text.title)
        #expect(tokens.selectedCardBorder == theme.accent)
        #expect(tokens.border == theme.panel.border)
    }

    /// Protection raises the panel like the chrome; it never goes below the board's 55 %.
    @Test func backgroundNeverDropsBelowTheBoard() {
        let tokens = Theme.obsidian.appearancePanel

        #expect(tokens.background(protectedAt: 0).alpha == 0.55)
        #expect(tokens.background(protectedAt: 0.89).alpha == 0.89)
    }
}
