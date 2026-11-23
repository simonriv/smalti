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

    /// `.kbd` border and the `0 0 0 1px` focus ring are 1 px in Main.dc.html.
    @Test func lineWidthTokens() {
        #expect(theme.kbd.borderWidth == 1)
        #expect(theme.focus.ringWidth == 1)
    }

    /// "+" button of the strip and the process name of the pane header, from Main.dc.html.
    @Test func stripAddButtonAndHeaderProcessTokens() {
        #expect(theme.strip.addButtonIconSize == 12)
        #expect(theme.strip.addButtonIconStroke == 1.4)
        #expect(theme.strip.addButtonColor == theme.text.secondary)
        #expect(theme.header.processFontWeight == 600)
    }

    /// One hairline width for the strip, header and status bar separators and the pill border; a header dot of its own.
    @Test func hairlineAndHeaderDotTokens() {
        #expect(theme.chrome.hairlineWidth == 1)
        #expect(theme.header.dot == theme.strip.dot)
    }

    @Test func focusTokensDeriveFromTheAccent() {
        #expect(theme.focus.ring == theme.accent.withAlpha(0x80 / 255))
        #expect(theme.focus.glow == theme.accent.withAlpha(0x22 / 255))
        #expect(theme.focus.glowRadius == 28)
    }

    /// The rest of Paleta.dc.html: field, icons, list padding, row padding, shadow, "actual" marker, footer gap.
    @Test func paletteDetailTokens() {
        let palette = theme.palette
        #expect(palette.fieldFontSize == 16)
        #expect(palette.fieldGap == 10)
        #expect(palette.iconSize == 16)
        #expect(palette.searchIconStroke == 1.5)
        #expect(palette.commandIconStroke == 1.4)
        #expect(palette.listPaddingTop == 4)
        #expect(palette.listPaddingHorizontal == 6)
        #expect(palette.listPaddingBottom == 8)
        #expect(palette.rowPadding == 12)
        #expect(palette.shadowOffsetY == 40)
        #expect(palette.shadowBlur == 100)
        #expect(palette.shadowOpacity == 0.55)
        #expect(palette.markerFontSize == 11.5)
        #expect(palette.footerGap == 16)
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

    /// Reanudar.dc.html, left column.
    @Test func resumeTokensMatchBoard() {
        let resume = theme.resume
        #expect(resume.contentWidth == 908)
        #expect(resume.paddingVertical == 28)
        #expect(resume.paddingHorizontal == 32)
        #expect(resume.titleFontSize == 20)
        #expect(resume.subtitleFontSize == 12.5)
        #expect(resume.rowCornerRadius == 9)
        #expect(resume.rowSelected == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.03))
        #expect(resume.buttonHeight == 36)
        #expect(resume.buttonCornerRadius == 8)
        #expect(resume.headerPadding == ResumeTokens.Insets(top: 4, horizontal: 12, bottom: 8))
        #expect(resume.hintGap == 6)
        #expect(resume.buttonBorderWidth == 1)
        #expect(theme.agent.stoppedRingWidth == 1)
    }

    @Test func restoreTagColorsMatchBoard() {
        #expect(theme.resume.agentTag == RGBAColor(red: 217, green: 119, blue: 87, alpha: 0.16))
        #expect(theme.resume.agentTagText == RGBAColor(red: 0xf0, green: 0xa9, blue: 0x8f, alpha: 1))
        #expect(theme.resume.programTag == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.07))
        #expect(theme.resume.programTagText == RGBAColor(red: 0xc3, green: 0xc7, blue: 0xcf, alpha: 1))
        #expect(theme.resume.primaryButtonText == RGBAColor(red: 0x0d, green: 0x0f, blue: 0x15, alpha: 1))
    }

    /// docs/design/README.md: verde trabajando, ámbar te espera, rojo error, círculo hueco detenido.
    @Test func agentStatusColorsMatchTheDesign() {
        #expect(theme.statusDot(for: .working) == .filled(RGBAColor(red: 0x9e, green: 0xce, blue: 0x6a, alpha: 1)))
        #expect(theme.statusDot(for: .waiting) == .filled(RGBAColor(red: 0xe0, green: 0xaf, blue: 0x68, alpha: 1)))
        #expect(theme.statusDot(for: .failed) == .filled(RGBAColor(red: 0xf7, green: 0x76, blue: 0x8e, alpha: 1)))
        #expect(
            theme.statusDot(for: .stopped) == .hollow(RGBAColor(red: 0x6b, green: 0x71, blue: 0x7c, alpha: 1), width: 1)
        )
        #expect(theme.statusDot(for: nil) == .filled(theme.strip.dot))
        #expect(theme.agent.waitingBorder == RGBAColor(red: 224, green: 175, blue: 104, alpha: 0.35))
        #expect(theme.agent.counterGap == 14)
        #expect(theme.agent.counterItemGap == 6)
        #expect(theme.agent.counterFontSize == 11.5)
        #expect(theme.agent.counterText == RGBAColor(red: 0x9a, green: 0xa0, blue: 0xab, alpha: 1))
    }
}
