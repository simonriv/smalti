import SmaltiCore
import Testing

/// `Prompt.dc.html`: the studio's sizes from the board, colors from the theme.
@Suite("Prompt studio tokens")
struct PromptStudioTokensTests {
    @Test func sizesAreTheBoards() {
        let tokens = Theme.obsidian.promptStudio

        #expect(tokens.asideWidth == 400)
        #expect(tokens.asidePaddingVertical == 22)
        #expect(tokens.asidePaddingHorizontal == 20)
        #expect(tokens.asideGap == 16)
        #expect(tokens.mainPaddingVertical == 24)
        #expect(tokens.mainPaddingHorizontal == 28)
        #expect(tokens.mainGap == 18)
        #expect(tokens.moduleRowHeight == 38)
        #expect(tokens.moduleRowGap == 2)
        #expect(tokens.buttonHeight == 34)
        #expect(tokens.previewFontSize == 13)
        #expect(tokens.templateFontSize == 11.5)
    }

    @Test func colorsFollowTheTheme() {
        let theme = ThemeCatalog.theme(.bosque)
        let tokens = theme.promptStudio

        #expect(tokens.applyBackground == theme.accent)
        #expect(tokens.applyText == theme.resume.primaryButtonText)
        #expect(tokens.handle == theme.agent.stopped)
        #expect(tokens.previewBackground == theme.panel.background.withAlpha(0.38))
    }
}
