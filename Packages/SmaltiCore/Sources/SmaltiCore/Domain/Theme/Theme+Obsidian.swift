// Sizes shared by every theme; the colors live in ThemeColors (Theme+Obsidian, +Niebla, +Amber, +Forest). Sources:
// docs/design/README.md, Apariencia.dc.html, Main.dc.html, Paleta.dc.html, Reanudar.dc.html and, for the F5 themes,
// docs/specs/F5-assets/generate-mockups.py (`THEMES`).

private let monospacedFontFamily = "JetBrains Mono"

extension Theme {
    public static let obsidian = Theme.make(name: "Obsidiana", colors: .obsidiana)

    /// Every theme shares these sizes; only `colors` change (spec F5, "Temas").
    static func make(name: String, colors c: ThemeColors) -> Theme {
        let line = { (alpha: Double) in c.hairline.withAlpha(alpha) }
        return Theme(
            name: name,
            window: WindowTokens(
                background: c.glass.withAlpha(0.62),
                blurRadius: 28,
                border: line(0.09),
                borderWidth: 1,
                cornerRadius: 16),
            panel: PanelTokens(
                background: c.panel.withAlpha(0.34),
                border: line(0.07),
                borderWidth: 1,
                cornerRadius: 11,
                gap: 8,
                areaPadding: 10),
            chrome: ChromeTokens(topStripHeight: 40, hairlineWidth: 1),
            text: TextTokens(
                interfaceFontFamily: "Inter", primary: c.primary, title: c.title,
                secondary: c.secondary, ghostText: c.ghost),
            accent: c.accent,
            terminal: TerminalAppearance(
                fontFamily: monospacedFontFamily,
                fontSize: 13,
                lineHeight: 1.62,
                foreground: c.primary,
                cursor: c.accent,
                palette: c.ansi,
                paddingX: 16,
                paddingY: 12),
            strip: StripTokens(
                pillHeight: 26, pillCornerRadius: 7, pillPadding: 11, pillGap: 6, paddingLeading: 16,
                paddingTrailing: 14, inactiveText: c.muted, activeText: c.title, labelGap: 7,
                fontSize: 12,
                fontWeight: 500, dotSize: 6, dot: c.neutralDot,
                bottomBorder: line(0.05), addButtonIconSize: 12, addButtonIconStroke: 1.4,
                addButtonColor: c.secondary),
            header: HeaderTokens(
                height: 30, padding: 12, gap: 8, fontSize: 11.5, dotSize: 7, dot: c.neutralDot,
                directory: c.muted,
                bottomBorder: line(0.05), processFontWeight: 600, contextBarWidth: 44, contextBarHeight: 4,
                contextBarTrack: line(0.08)),
            kbd: KbdTokens(
                fontFamily: monospacedFontFamily, fontSize: 10.5, paddingVertical: 2, paddingHorizontal: 6,
                cornerRadius: 5, borderWidth: 1, border: line(0.12), text: c.kbdText, background: line(0.04)),
            statusBar: StatusBarTokens(
                height: 28, padding: 16, gap: 16, fontSize: 11, text: c.secondary, topBorder: line(0.05),
                todayTokens: c.strong),
            focus: FocusTokens(
                ring: c.accent.withAlpha(0x80 / 255), glow: c.accent.withAlpha(0x22 / 255), glowRadius: 28,
                ringWidth: 1),
            palette: PaletteTokens(
                width: 640, cornerRadius: 14, background: c.overlay.withAlpha(0.82),
                blurRadius: 36, border: line(0.12), fieldHeight: 52, fieldPadding: 16, rowHeight: 38,
                rowCornerRadius: 8, rowGap: 12, rowFontSize: 13.5, groupFontSize: 10.5, groupTracking: 0.06,
                groupPaddingTop: 10, groupPaddingHorizontal: 12, groupPaddingBottom: 4,
                selection: c.accent.withAlpha(0x26 / 255), footerHeight: 36, footerFontSize: 11.5,
                footerBorder: line(0.07), topOffset: 110, panelsBackdropOpacity: 0.45, fieldFontSize: 16, fieldGap: 10,
                iconSize: 16, searchIconStroke: 1.5, commandIconStroke: 1.4, listPaddingTop: 4,
                listPaddingHorizontal: 6,
                listPaddingBottom: 8, rowPadding: 12, shadowOffsetY: 40, shadowBlur: 100,
                shadowOpacity: c.overlayShadowOpacity,
                markerFontSize: 11.5, footerGap: 16),
            motion: MotionTokens(rearrangeDuration: 0.15, overlayAppearDuration: 0.12),
            emptyState: EmptyStateTokens(fontSize: 13, lineGap: 8, text: c.secondary),
            resume: ResumeTokens(
                contentWidth: 908, paddingVertical: 28, paddingHorizontal: 32, blockGap: 18, titleFontSize: 20,
                titleGap: 6, subtitleFontSize: 12.5, subtitleText: c.muted, sectionPadding: 10,
                sectionRowGap: 2, headerGap: 10, workspaceFontSize: 13, summaryFontSize: 11.5, rowPaddingVertical: 9,
                rowPaddingHorizontal: 12, rowGap: 12, rowCornerRadius: 9, rowFontSize: 13, rowSelected: line(0.03),
                checkboxSize: 16, tagFontSize: 10.5, tagPaddingVertical: 2, tagPaddingHorizontal: 7,
                agentTag: RGBAColor(red: 217, green: 119, blue: 87, alpha: 0.16), agentTagText: c.agentTagText,
                programTag: line(0.07), programTagText: c.strong, finishedText: c.muted,
                codeFontSize: 11.5, buttonHeight: 36, buttonPaddingHorizontal: 16, buttonCornerRadius: 8,
                buttonFontSize: 13, buttonGap: 10, primaryButtonText: c.onAccent, secondaryButtonBorder: line(0.12),
                tertiaryButtonText: c.muted, hintFontSize: 11.5,
                headerPadding: ResumeTokens.Insets(top: 4, horizontal: 12, bottom: 8), hintGap: 6, buttonBorderWidth: 1,
                titleWeight: 600, workspaceWeight: 600, tagWeight: 500, primaryButtonWeight: 600, buttonWeight: 500),
            agent: AgentStatusTokens(
                working: c.working, waiting: c.waiting, failed: c.failed, stopped: c.stopped,
                stoppedRingWidth: 1, waitingBorder: c.waiting.withAlpha(0.35), counterGap: 14,
                counterItemGap: 6, counterFontSize: 11.5, counterText: c.muted),
            observatory: ObservatoryTokens(
                stripTitleSize: 13, stripTitleWeight: 600, pillWeight: 500, stripSubtitleSize: 12, stripGap: 10,
                stripPaddingLeading: 18, stripPaddingTrailing: 14,
                pillHeight: 26, pillPadding: 10, pillRadius: 7, pillFontSize: 12, pillBorder: line(0.08),
                pillText: c.strong, padding: 14, gap: 12, sideColumnWidth: 330, cardGap: 10,
                cardBackground: c.panel.withAlpha(0.34), cardBorder: line(0.06), cardRadius: 11,
                cardPaddingVertical: 12, cardPaddingHorizontal: 14, labelSize: 10.5, labelTracking: 0.06, valueSize: 26,
                noteSize: 11.5, tableHeaderHeight: 34, rowHeight: 44, rowFontSize: 12.5, rowBorder: line(0.04),
                cellPadding: 10, columns: [112, nil, nil, 76, 76, 70, 118, 56, 66], tableDot: 7, contextBarWidth: 56,
                activityFontSize: 12, activityRowGap: 6, activityTimeWidth: 52, activityToolWidth: 64, chartHeight: 110,
                chartLineWidth: 1.6, chartPeakRadius: 3, chartGrid: line(0.08), chartGridFaint: line(0.05),
                sparklineHeight: 34, sparklineWidth: 1.4, cpu: c.ansi[6], gpu: c.ansi[5],
                memoryModel: c.ansi[5],
                memoryRest: c.stopped, memoryTrack: line(0.07), memoryBarHeight: 8, separator: line(0.05),
                footnoteSize: 11, modelNameSize: 13, systemRowSize: 12, fadeDuration: 0.15,
                spacing: ObservatorySpacing(
                    cardStack: 6, stateDot: 7, contextBar: 8, selectionBar: 2, detailColumns: 18, detailStack: 8,
                    detailRatio: 1.2, activityColumns: 10, chartLabelSize: 10, localModels: 10, modelLines: 4,
                    system: 14,
                    systemGroup: 6)),
            inputMenu: InputMenuTokens(
                width: 360, cornerRadius: 10, border: line(0.1),
                background: c.menu.withAlpha(0.94),
                shadowRadius: 40, shadowOffsetY: 18, shadowOpacity: c.menuShadowOpacity, padding: 5, rowFontSize: 12,
                rowHeight: 29.4,
                rowGap: 1, rowCornerRadius: 6, rowPaddingHorizontal: 8, nameColumnWidth: 92, columnGap: 10,
                footerHeight: 24, footerFontSize: 10.5, footerTopGap: 4, textLineHeight: 1.4, cursorGap: 4,
                rowsBelowCursor: 6, maximumVisibleRows: 8),
            historyPalette: HistoryPaletteTokens(
                widthFraction: 0.86, minimumWidth: 480, maximumWidth: 720, topOffset: 26, chipCornerRadius: 6,
                chipBorder: line(0.1), chipActiveBorderAlpha: 0.5, chipPaddingHorizontal: 7, chipPaddingVertical: 2,
                listInset: 6, rowHeight: 32, rowPaddingHorizontal: 10, rowGap: 10, commandFontSize: 12, dotSize: 9,
                visibleRows: 8),
            help: HelpTokens(width: 760, maximumHeight: 560, topOffset: 60, columnGap: 8, rowHeight: 27),
            feedback: FeedbackTokens(
                width: 520, topOffset: 160, padding: 20, titleFontSize: 15, choiceHeight: 38, choiceGap: 8,
                noteFontSize: 12, summaryFontSize: 12, ideaDot: c.ansi[5]),
            searchBar: SearchBarTokens(width: 340, height: 36))
    }
}
