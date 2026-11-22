// The only file with literal design tokens. Source: docs/design/README.md and Apariencia.dc.html.

private func rgb(_ value: UInt32) -> RGBAColor {
    RGBAColor(
        red: UInt8(truncatingIfNeeded: value >> 16),
        green: UInt8(truncatingIfNeeded: value >> 8),
        blue: UInt8(truncatingIfNeeded: value),
        alpha: 1)
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
            cornerRadius: 16),
        panel: PanelTokens(
            background: RGBAColor(red: 6, green: 7, blue: 10, alpha: 0.34),
            border: RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.07),
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
            paddingY: 12))
}
