// The only file with literal design tokens. Sources: docs/design/README.md, Apariencia.dc.html, Main.dc.html and
// Paleta.dc.html and Reanudar.dc.html.

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

private let monospacedFontFamily = "JetBrains Mono"
private let obsidianAccent = rgb(0x7aa2f7)
private let obsidianPrimaryText = rgb(0xd7dae0)
private let obsidianTitleText = rgb(0xe6e9ef)
/// Minimum for small text over the glass (docs/design/README.md); status bar and empty hint use it too.
private let obsidianSecondaryText = rgb(0x8b919c)
/// Status dot before agents have a state (F2 colors it).
private let obsidianNeutralDot = rgb(0x565c68)
/// Inactive workspace names and pane directories (Main.dc.html).
private let obsidianMutedText = rgb(0x9aa0ab)

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
        chrome: ChromeTokens(topStripHeight: 40, hairlineWidth: 1),
        text: TextTokens(
            interfaceFontFamily: "Inter", primary: obsidianPrimaryText, title: obsidianTitleText,
            secondary: obsidianSecondaryText),
        accent: obsidianAccent,
        terminal: TerminalAppearance(
            fontFamily: monospacedFontFamily,
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
            paddingTrailing: 14, inactiveText: obsidianMutedText, activeText: obsidianTitleText, labelGap: 7,
            fontSize: 12,
            fontWeight: 500, dotSize: 6, dot: obsidianNeutralDot,
            bottomBorder: white(0.05), addButtonIconSize: 12, addButtonIconStroke: 1.4,
            addButtonColor: obsidianSecondaryText),
        header: HeaderTokens(
            height: 30, padding: 12, gap: 8, fontSize: 11.5, dotSize: 7, dot: obsidianNeutralDot,
            directory: obsidianMutedText,
            bottomBorder: white(0.05), processFontWeight: 600),
        kbd: KbdTokens(
            fontFamily: monospacedFontFamily, fontSize: 10.5, paddingVertical: 2, paddingHorizontal: 6,
            cornerRadius: 5, borderWidth: 1, border: white(0.12), text: rgb(0xaeb3bd), background: white(0.04)),
        statusBar: StatusBarTokens(
            height: 28, padding: 16, gap: 16, fontSize: 11, text: obsidianSecondaryText, topBorder: white(0.05)),
        focus: FocusTokens(
            ring: obsidianAccent.withAlpha(0x80 / 255), glow: obsidianAccent.withAlpha(0x22 / 255), glowRadius: 28,
            ringWidth: 1),
        palette: PaletteTokens(
            width: 640, cornerRadius: 14, background: RGBAColor(red: 20, green: 22, blue: 30, alpha: 0.82),
            blurRadius: 36, border: white(0.12), fieldHeight: 52, fieldPadding: 16, rowHeight: 38,
            rowCornerRadius: 8, rowGap: 12, rowFontSize: 13.5, groupFontSize: 10.5, groupTracking: 0.06,
            groupPaddingTop: 10, groupPaddingHorizontal: 12, groupPaddingBottom: 4,
            selection: obsidianAccent.withAlpha(0x26 / 255), footerHeight: 36, footerFontSize: 11.5,
            footerBorder: white(0.07), topOffset: 110, panelsBackdropOpacity: 0.45, fieldFontSize: 16, fieldGap: 10,
            iconSize: 16, searchIconStroke: 1.5, commandIconStroke: 1.4, listPaddingTop: 4, listPaddingHorizontal: 6,
            listPaddingBottom: 8, rowPadding: 12, shadowOffsetY: 40, shadowBlur: 100, shadowOpacity: 0.55,
            markerFontSize: 11.5, footerGap: 16),
        motion: MotionTokens(rearrangeDuration: 0.15),
        emptyState: EmptyStateTokens(fontSize: 13, lineGap: 8, text: obsidianSecondaryText),
        resume: ResumeTokens(
            contentWidth: 908, paddingVertical: 28, paddingHorizontal: 32, blockGap: 18, titleFontSize: 20,
            titleGap: 6, subtitleFontSize: 12.5, subtitleText: obsidianMutedText, sectionPadding: 10,
            sectionRowGap: 2, headerGap: 10, workspaceFontSize: 13, summaryFontSize: 11.5, rowPaddingVertical: 9,
            rowPaddingHorizontal: 12, rowGap: 12, rowCornerRadius: 9, rowFontSize: 13, rowSelected: white(0.03),
            checkboxSize: 16, tagFontSize: 10.5, tagPaddingVertical: 2, tagPaddingHorizontal: 7,
            agentTag: RGBAColor(red: 217, green: 119, blue: 87, alpha: 0.16), agentTagText: rgb(0xf0a98f),
            programTag: white(0.07), programTagText: rgb(0xc3c7cf), finishedText: obsidianMutedText,
            codeFontSize: 11.5, buttonHeight: 36, buttonPaddingHorizontal: 16, buttonCornerRadius: 8,
            buttonFontSize: 13, buttonGap: 10, primaryButtonText: rgb(0x0d0f15), secondaryButtonBorder: white(0.12),
            tertiaryButtonText: obsidianMutedText, hintFontSize: 11.5,
            headerPadding: ResumeTokens.Insets(top: 4, horizontal: 12, bottom: 8), hintGap: 6, buttonBorderWidth: 1,
            titleWeight: 600, workspaceWeight: 600, tagWeight: 500, primaryButtonWeight: 600, buttonWeight: 500),
        agent: AgentStatusTokens(
            working: rgb(0x9ece6a), waiting: rgb(0xe0af68), failed: rgb(0xf7768e), stopped: rgb(0x6b717c),
            stoppedRingWidth: 1, waitingBorder: RGBAColor(red: 224, green: 175, blue: 104, alpha: 0.35), counterGap: 14,
            counterItemGap: 6, counterFontSize: 11.5, counterText: obsidianMutedText))
}
