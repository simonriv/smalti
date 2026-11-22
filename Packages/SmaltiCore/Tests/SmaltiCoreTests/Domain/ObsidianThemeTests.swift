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

    @Test func interfaceTypefaceIsInter() {
        #expect(theme.text.interfaceFontFamily == "Inter")
    }

    @Test func kbdTypefaceReusesTheTerminalFamily() {
        #expect(theme.kbd.fontFamily == theme.terminal.fontFamily)
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

    private func white(_ alpha: Double) -> RGBAColor { RGBAColor(red: 255, green: 255, blue: 255, alpha: alpha) }

    @Test func stripTokens() throws {
        let strip = theme.strip

        #expect(strip.pillHeight == 26)
        #expect(strip.pillCornerRadius == 7)
        #expect(strip.pillPadding == 11)
        #expect(strip.pillGap == 6)
        #expect(strip.paddingLeading == 16)
        #expect(strip.paddingTrailing == 14)
        #expect(strip.inactiveText == (try RGBAColor(hex: "#9aa0ab")))
        #expect(strip.labelGap == 7)
        #expect(strip.fontSize == 12)
        #expect(strip.fontWeight == 500)
        #expect(strip.activeText == theme.text.title)
        #expect(strip.dotSize == 6)
        #expect(strip.dot == (try RGBAColor(hex: "#565c68")))
        #expect(strip.bottomBorder == white(0.05))
    }

    @Test func headerTokens() throws {
        let header = theme.header

        #expect(header.height == 30)
        #expect(header.padding == 12)
        #expect(header.gap == 8)
        #expect(header.fontSize == 11.5)
        #expect(header.dotSize == 7)
        #expect(header.directory == (try RGBAColor(hex: "#9aa0ab")))
        #expect(header.bottomBorder == white(0.05))
    }

    @Test func kbdTokens() throws {
        let kbd = theme.kbd

        #expect(kbd.fontFamily == "JetBrains Mono")
        #expect(kbd.fontSize == 10.5)
        #expect(kbd.paddingVertical == 2)
        #expect(kbd.paddingHorizontal == 6)
        #expect(kbd.cornerRadius == 5)
        #expect(kbd.border == white(0.12))
        #expect(kbd.text == (try RGBAColor(hex: "#aeb3bd")))
        #expect(kbd.background == white(0.04))
    }

    @Test func statusBarTokens() throws {
        let bar = theme.statusBar

        #expect(bar.height == 28)
        #expect(bar.padding == 16)
        #expect(bar.gap == 16)
        #expect(bar.fontSize == 11)
        #expect(bar.text == (try RGBAColor(hex: "#8b919c")))
        #expect(bar.topBorder == white(0.05))
    }

    @Test func focusTokensDeriveFromTheAccent() {
        #expect(theme.focus.ring == theme.accent.withAlpha(0x80 / 255))
        #expect(theme.focus.glow == theme.accent.withAlpha(0x22 / 255))
        #expect(theme.focus.glowRadius == 28)
    }

    @Test func paletteTokens() {
        let palette = theme.palette

        #expect(palette.width == 640)
        #expect(palette.cornerRadius == 14)
        #expect(palette.background == RGBAColor(red: 20, green: 22, blue: 30, alpha: 0.82))
        #expect(palette.blurRadius == 36)
        #expect(palette.border == white(0.12))
        #expect(palette.fieldHeight == 52)
        #expect(palette.fieldPadding == 16)
        #expect(palette.rowHeight == 38)
        #expect(palette.rowCornerRadius == 8)
        #expect(palette.rowGap == 12)
        #expect(palette.rowFontSize == 13.5)
        #expect(palette.groupFontSize == 10.5)
        #expect(palette.groupTracking == 0.06)
        #expect(palette.groupPaddingTop == 10)
        #expect(palette.groupPaddingHorizontal == 12)
        #expect(palette.groupPaddingBottom == 4)
        #expect(palette.selection == theme.accent.withAlpha(0x26 / 255))
        #expect(palette.footerHeight == 36)
        #expect(palette.footerFontSize == 11.5)
        #expect(palette.footerBorder == white(0.07))
        #expect(palette.topOffset == 110)
        #expect(palette.panelsBackdropOpacity == 0.45)
    }

    /// Empty workspace hint (decided by Simón, 2026-11-22): Inter 13 in the secondary text color.
    @Test func emptyStateTokens() {
        #expect(theme.emptyState.fontSize == 13)
        #expect(theme.emptyState.lineGap == 8)
        #expect(theme.emptyState.text == theme.text.secondary)
    }

    @Test func motionTokens() {
        #expect(theme.motion.rearrangeDuration == 0.15)
    }
}
