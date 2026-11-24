import SmaltiCore
import Testing

/// Spec F5.5: the preview card of `Main.dc.html`, sizes from the board, colors from the theme.
@Suite("Preview card tokens")
struct PreviewTokensTests {
    @Test func sizesAreTheBoards() {
        let tokens = Theme.obsidian.previewCard

        #expect(tokens.width == 210)
        #expect(tokens.cornerRadius == 10)
        #expect(tokens.padding == 8)
        #expect(tokens.gap == 6)
        #expect(tokens.imageSize == Size(width: 194, height: 104))
        #expect(tokens.imageCornerRadius == 6)
        #expect(tokens.captionFontSize == 10.5)
        #expect(tokens.shadowRadius == 40)
        #expect(tokens.shadowOffsetY == 18)
        #expect(tokens.anchorGap == 4)
    }

    @Test func obsidianColorsAreTheBoards() {
        let tokens = Theme.obsidian.previewCard

        #expect(tokens.caption.hexString == "#aeb3bd")
        #expect(tokens.background == RGBAColor(red: 18, green: 20, blue: 27, alpha: 0.92))
        #expect(tokens.border == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.12))
    }

    @Test(arguments: ThemeID.allCases)
    func colorsFollowTheTheme(_ id: ThemeID) {
        let theme = ThemeCatalog.theme(id)
        let tokens = theme.previewCard

        #expect(tokens.background == theme.inputMenu.background.withAlpha(0.92))
        #expect(tokens.border == theme.kbd.border)
        #expect(tokens.caption == theme.kbd.text)
        #expect(tokens.shadowOpacity == theme.palette.shadowOpacity)
    }

    @Test(arguments: ThemeID.allCases)
    func captionReaches4_5WithProtection(_ id: ThemeID) {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = id
        let theme = ThemeCatalog.apply(appearance).theme
        let tokens = theme.previewCard
        let ground = id.worstBackdrop.color.underneath(theme.window.background)
            .underneath(theme.panel.background).underneath(tokens.background)

        #expect(ContrastRatio.between(tokens.caption, ground) >= 4.5, "\(id): \(tokens.caption.hexString)")
    }
}
