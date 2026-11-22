// The only file with literal design tokens. Source: docs/design/README.md and Apariencia.dc.html.

private func rgb(_ value: UInt32) -> RGBAColor {
    RGBAColor(
        red: UInt8(truncatingIfNeeded: value >> 16),
        green: UInt8(truncatingIfNeeded: value >> 8),
        blue: UInt8(truncatingIfNeeded: value),
        alpha: 1)
}

private func white(_ alpha: Double) -> RGBAColor {
    RGBAColor(red: 255, green: 255, blue: 255, alpha: alpha)
}

private let obsidianAccent = rgb(0x7aa2f7)
private let obsidianPrimaryText = rgb(0xd7dae0)

extension Theme {
    public static let obsidian = Theme(
        name: "Obsidiana",
        window: WindowTokens(
            background: RGBAColor(red: 13, green: 15, blue: 21, alpha: 0.62),
            blurRadius: 28,
            border: RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.09),
            borderWidth: 1,
            cornerRadius: 16),
        panel: PanelTokens(
            background: RGBAColor(red: 6, green: 7, blue: 10, alpha: 0.34),
            border: RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.07),
            borderWidth: 1,
            cornerRadius: 11,
            gap: 8,
            areaPadding: 10),
        chrome: ChromeTokens(topStripHeight: 40),
        text: TextTokens(primary: obsidianPrimaryText, title: rgb(0xe6e9ef), secondary: rgb(0x8b919c)),
        accent: obsidianAccent,
        terminal: TerminalAppearance(
            fontFamily: "JetBrains Mono",
            fontSize: 13,
            lineHeight: 1.62,
            foreground: obsidianPrimaryText,
            cursor: obsidianAccent,
            palette: [
                0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
                0x414868, 0xff99ad, 0xb9f27c, 0xffc777, 0xa3bdfa, 0xd3b8ff, 0xa4e3ff, 0xc0caf5,
            ].map(rgb),
            paddingX: 16,
            paddingY: 12),
        strip: StripTokens(
            pillHeight: 26, pillCornerRadius: 7, pillPadding: 11, pillGap: 6, paddingLeading: 16,
            paddingTrailing: 14, inactiveText: rgb(0x9aa0ab), dotSize: 6, dot: rgb(0x565c68),
            bottomBorder: white(0.05)),
        header: HeaderTokens(
            height: 30, padding: 12, gap: 8, fontSize: 11.5, dotSize: 7, directory: rgb(0x9aa0ab),
            bottomBorder: white(0.05)),
        kbd: KbdTokens(
            fontFamily: "JetBrains Mono", fontSize: 10.5, paddingVertical: 2, paddingHorizontal: 6,
            cornerRadius: 5, border: white(0.12), text: rgb(0xaeb3bd), background: white(0.04)),
        statusBar: StatusBarTokens(
            height: 28, padding: 16, gap: 16, fontSize: 11, text: rgb(0x8b919c), topBorder: white(0.05)),
        focus: FocusTokens(
            ring: obsidianAccent.withAlpha(0x80 / 255), glow: obsidianAccent.withAlpha(0x22 / 255), glowRadius: 28),
        palette: PaletteTokens(
            width: 640, cornerRadius: 14, background: RGBAColor(red: 20, green: 22, blue: 30, alpha: 0.82),
            blurRadius: 36, border: white(0.12), fieldHeight: 52, fieldPadding: 16, rowHeight: 38,
            rowCornerRadius: 8, rowGap: 12, rowFontSize: 13.5, groupFontSize: 10.5, groupTracking: 0.06,
            groupPaddingTop: 10, groupPaddingHorizontal: 12, groupPaddingBottom: 4,
            selection: obsidianAccent.withAlpha(0x26 / 255), footerHeight: 36, footerFontSize: 11.5,
            footerBorder: white(0.07), topOffset: 110, panelsBackdropOpacity: 0.45),
        motion: MotionTokens(rearrangeDuration: 0.15))
}
