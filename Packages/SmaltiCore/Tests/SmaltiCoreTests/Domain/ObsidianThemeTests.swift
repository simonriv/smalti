import SmaltiCore
import Testing

@Suite("Obsidian theme matches docs/design/README.md")
struct ObsidianThemeTests {
    private let theme = Theme.obsidian

    @Test func windowTokens() {
        #expect(theme.window.background == RGBAColor(red: 13, green: 15, blue: 21, alpha: 0.62))
        #expect(theme.window.blurRadius == 28)
        #expect(theme.window.border == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.09))
        #expect(theme.window.cornerRadius == 16)
        #expect(theme.window.borderWidth == 1)
    }

    @Test func panelTokens() {
        #expect(theme.panel.background == RGBAColor(red: 6, green: 7, blue: 10, alpha: 0.34))
        #expect(theme.panel.border == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.07))
        #expect(theme.panel.cornerRadius == 11)
        #expect(theme.panel.gap == 8)
        #expect(theme.panel.areaPadding == 10)
        #expect(theme.panel.borderWidth == 1)
    }

    @Test func chromeTokens() {
        #expect(theme.chrome.topStripHeight == 40)
    }

    @Test func textAndAccentTokens() throws {
        #expect(theme.text.primary == (try RGBAColor(hex: "#d7dae0")))
        #expect(theme.text.title == (try RGBAColor(hex: "#e6e9ef")))
        #expect(theme.text.secondary == (try RGBAColor(hex: "#8b919c")))
        #expect(theme.accent == (try RGBAColor(hex: "#7aa2f7")))
    }

    @Test func terminalAppearance() throws {
        let terminal = theme.terminal

        #expect(terminal.fontFamily == "JetBrains Mono")
        #expect(terminal.fontSize == 13)
        #expect(terminal.lineHeight == 1.62)
        #expect(terminal.foreground == (try RGBAColor(hex: "#d7dae0")))
        #expect(terminal.cursor == theme.accent)
        #expect(terminal.paddingX == 16)
        #expect(terminal.paddingY == 12)
    }

    @Test func ansiPaletteMatchesAppearanceBoard() throws {
        let expected = try [
            "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#ff99ad", "#b9f27c", "#ffc777", "#a3bdfa", "#d3b8ff", "#a4e3ff", "#c0caf5",
        ].map { try RGBAColor(hex: $0) }

        #expect(theme.terminal.palette == expected)
    }
}
