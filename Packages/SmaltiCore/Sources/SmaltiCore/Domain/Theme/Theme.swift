/// Visual tokens shared by the window chrome and the terminal engine.
public struct Theme: Equatable, Sendable {
    public let name: String
    public let window: WindowTokens
    public let panel: PanelTokens
    public let chrome: ChromeTokens
    public let text: TextTokens
    public let accent: RGBAColor
    public let terminal: TerminalAppearance
    public let strip: StripTokens
    public let header: HeaderTokens
    public let kbd: KbdTokens
    public let statusBar: StatusBarTokens
    public let focus: FocusTokens
    public let palette: PaletteTokens
    public let motion: MotionTokens
    public let emptyState: EmptyStateTokens
    public let resume: ResumeTokens
    public let agent: AgentStatusTokens
    public let observatory: ObservatoryTokens
}

/// The agent state colours, always the same (docs/design/README.md): green working, amber waiting, red failed,
/// a hollow grey circle when stopped.
public struct AgentStatusTokens: Equatable, Sendable {
    public let working: RGBAColor
    public let waiting: RGBAColor
    public let failed: RGBAColor
    public let stopped: RGBAColor
    public let stoppedRingWidth: Double
    /// Border of a pane whose agent waits, when it has no focus (Main.dc.html).
    public let waitingBorder: RGBAColor
    /// Counters right of the workspace pills: "2 trabajando · 1 te espera".
    public let counterGap: Double
    public let counterItemGap: Double
    public let counterFontSize: Double
    public let counterText: RGBAColor
}

/// How a status dot is drawn.
public enum StatusDotStyle: Equatable, Sendable {
    case filled(RGBAColor)
    case hollow(RGBAColor, width: Double)
}

extension Theme {
    /// A pane or workspace without agents keeps the neutral dot of F1.
    public func statusDot(for kind: AgentStateKind?) -> StatusDotStyle {
        switch kind {
        case .working: .filled(agent.working)
        case .waiting: .filled(agent.waiting)
        case .failed: .filled(agent.failed)
        case .stopped: .hollow(agent.stopped, width: agent.stoppedRingWidth)
        case nil: .filled(strip.dot)
        }
    }
}

public struct WindowTokens: Equatable, Sendable {
    public let background: RGBAColor
    public let blurRadius: Double
    public let border: RGBAColor
    public let borderWidth: Double
    public let cornerRadius: Double
}

public struct PanelTokens: Equatable, Sendable {
    public let background: RGBAColor
    public let border: RGBAColor
    public let borderWidth: Double
    public let cornerRadius: Double
    public let gap: Double
    public let areaPadding: Double
}

public struct ChromeTokens: Equatable, Sendable {
    public let topStripHeight: Double
    /// Separators under the strip, the pane headers and above the status bar, and the pill border, in points.
    public let hairlineWidth: Double
}

public struct TextTokens: Equatable, Sendable {
    public let interfaceFontFamily: String
    public let primary: RGBAColor
    public let title: RGBAColor
    public let secondary: RGBAColor
}

public struct TerminalAppearance: Equatable, Sendable {
    public let fontFamily: String
    public let fontSize: Double
    public let lineHeight: Double
    public let foreground: RGBAColor
    public let cursor: RGBAColor
    /// The 16 ANSI colors, normal 0–7 then bright 8–15.
    public let palette: [RGBAColor]
    public let paddingX: Double
    public let paddingY: Double
}

/// Workspace strip: the pills at the top of the window.
public struct StripTokens: Equatable, Sendable {
    public let pillHeight: Double
    public let pillCornerRadius: Double
    public let pillPadding: Double
    public let pillGap: Double
    public let paddingLeading: Double
    public let paddingTrailing: Double
    public let inactiveText: RGBAColor
    public let activeText: RGBAColor
    /// Gap between a pill's dot and its label.
    public let labelGap: Double
    public let fontSize: Double
    public let fontWeight: Int
    public let dotSize: Double
    public let dot: RGBAColor
    public let bottomBorder: RGBAColor
    /// The "+" (new workspace) button: a square as tall as a pill with a thin cross.
    public let addButtonIconSize: Double
    public let addButtonIconStroke: Double
    public let addButtonColor: RGBAColor
}

/// The bar above each pane.
public struct HeaderTokens: Equatable, Sendable {
    public let height: Double
    public let padding: Double
    public let gap: Double
    public let fontSize: Double
    public let dotSize: Double
    /// Neutral in F1; F2 colors it by agent state.
    public let dot: RGBAColor
    public let directory: RGBAColor
    public let bottomBorder: RGBAColor
    /// The process name is semibold in the title color.
    public let processFontWeight: Int
    /// "ctx 41%" bar of a working agent (Main.dc.html: 44 × 4, radius 2, track white 8 %).
    public let contextBarWidth: Double
    public let contextBarHeight: Double
    public let contextBarTrack: RGBAColor
}

/// Keycap-style label that shows a shortcut.
public struct KbdTokens: Equatable, Sendable {
    public let fontFamily: String
    public let fontSize: Double
    public let paddingVertical: Double
    public let paddingHorizontal: Double
    public let cornerRadius: Double
    public let borderWidth: Double
    public let border: RGBAColor
    public let text: RGBAColor
    public let background: RGBAColor
}

public struct StatusBarTokens: Equatable, Sendable {
    public let height: Double
    public let padding: Double
    public let gap: Double
    public let fontSize: Double
    public let text: RGBAColor
    public let topBorder: RGBAColor
    /// "hoy 1.24M tokens", a step brighter than the other figures.
    public let todayTokens: RGBAColor
}

/// Focused-pane highlight. Both colors are the accent at a fixed opacity.
public struct FocusTokens: Equatable, Sendable {
    public private(set) var ring: RGBAColor
    public private(set) var glow: RGBAColor
    public let glowRadius: Double
    /// Width of the glow ring stroked just outside the pane border (`0 0 0 1px`); the border itself, in the ring
    /// color, uses `PanelTokens.borderWidth`.
    public let ringWidth: Double

    func following(_ accent: RGBAColor) -> FocusTokens {
        var copy = self
        copy.ring = accent.withAlpha(ring.alpha)
        copy.glow = accent.withAlpha(glow.alpha)
        return copy
    }
}

/// The ⌘K command palette.
public struct PaletteTokens: Equatable, Sendable {
    public let width: Double
    public let cornerRadius: Double
    public let background: RGBAColor
    public let blurRadius: Double
    public let border: RGBAColor
    public let fieldHeight: Double
    public let fieldPadding: Double
    public let rowHeight: Double
    public let rowCornerRadius: Double
    public let rowGap: Double
    public let rowFontSize: Double
    public let groupFontSize: Double
    /// In em.
    public let groupTracking: Double
    public let groupPaddingTop: Double
    public let groupPaddingHorizontal: Double
    public let groupPaddingBottom: Double
    /// The accent at a fixed opacity.
    public private(set) var selection: RGBAColor
    public let footerHeight: Double
    public let footerFontSize: Double
    public let footerBorder: RGBAColor
    public let topOffset: Double
    /// Opacity of the layer that dims the panes behind the palette.
    public let panelsBackdropOpacity: Double
    public let fieldFontSize: Double
    /// Space between the search icon, the field and the `esc` hint.
    public let fieldGap: Double
    public let iconSize: Double
    public let searchIconStroke: Double
    public let commandIconStroke: Double
    public let listPaddingTop: Double
    public let listPaddingHorizontal: Double
    public let listPaddingBottom: Double
    public let rowPadding: Double
    /// `0 40px 100px rgba(0,0,0,0.55)`.
    public let shadowOffsetY: Double
    public let shadowBlur: Double
    public let shadowOpacity: Double
    /// "actual" next to the current layout.
    public let markerFontSize: Double
    public let footerGap: Double

    func following(_ accent: RGBAColor) -> PaletteTokens {
        var copy = self
        copy.selection = accent.withAlpha(selection.alpha)
        return copy
    }
}

/// Hint shown in a workspace with no panes (not on the boards; decided by Simón, 2026-11-22).
public struct EmptyStateTokens: Equatable, Sendable {
    public let fontSize: Double
    /// Vertical space between the title and the shortcut line.
    public let lineGap: Double
    public let text: RGBAColor
}

/// "Retomar donde quedaste" (Reanudar.dc.html, left column). The primary button is the accent.
public struct ResumeTokens: Equatable, Sendable {
    /// The board's left column: the window minus its 420 pt session list (F6).
    public let contentWidth: Double
    public let paddingVertical: Double
    public let paddingHorizontal: Double
    public let blockGap: Double
    public let titleFontSize: Double
    public let titleGap: Double
    public let subtitleFontSize: Double
    public let subtitleText: RGBAColor
    public let sectionPadding: Double
    public let sectionRowGap: Double
    public let headerGap: Double
    public let workspaceFontSize: Double
    public let summaryFontSize: Double
    public let rowPaddingVertical: Double
    public let rowPaddingHorizontal: Double
    public let rowGap: Double
    public let rowCornerRadius: Double
    public let rowFontSize: Double
    public let rowSelected: RGBAColor
    public let checkboxSize: Double
    public let tagFontSize: Double
    public let tagPaddingVertical: Double
    public let tagPaddingHorizontal: Double
    public let agentTag: RGBAColor
    public let agentTagText: RGBAColor
    public let programTag: RGBAColor
    public let programTagText: RGBAColor
    public let finishedText: RGBAColor
    public let codeFontSize: Double
    public let buttonHeight: Double
    public let buttonPaddingHorizontal: Double
    public let buttonCornerRadius: Double
    public let buttonFontSize: Double
    public let buttonGap: Double
    public let primaryButtonText: RGBAColor
    public let secondaryButtonBorder: RGBAColor
    public let tertiaryButtonText: RGBAColor
    public let hintFontSize: Double
    /// Workspace heading inside its section: `padding: 4px 12px 8px`.
    public let headerPadding: Insets
    /// Between the "Siempre restaurar" checkbox, its text and its `kbd`.
    public let hintGap: Double
    public let buttonBorderWidth: Double
    /// CSS font weights of the board.
    public let titleWeight: Int
    public let workspaceWeight: Int
    public let tagWeight: Int
    public let primaryButtonWeight: Int
    public let buttonWeight: Int

    public struct Insets: Equatable, Sendable {
        public let top: Double
        public let horizontal: Double
        public let bottom: Double

        public init(top: Double, horizontal: Double, bottom: Double) {
            self.top = top
            self.horizontal = horizontal
            self.bottom = bottom
        }
    }
}

public struct MotionTokens: Equatable, Sendable {
    /// Seconds a pane takes to move to its new place; disabled by "Reducir movimiento".
    public let rearrangeDuration: Double
}

extension Theme {
    /// This theme with the user's appearance settings on top. Tokens that are the accent at some opacity follow it.
    public func applying(_ appearance: AppearanceSettings) -> Theme {
        Theme(
            name: name,
            window: WindowTokens(
                background: window.background.withAlpha(appearance.glassOpacity),
                blurRadius: appearance.blur, border: window.border, borderWidth: window.borderWidth,
                cornerRadius: window.cornerRadius),
            panel: PanelTokens(
                background: panel.background, border: panel.border, borderWidth: panel.borderWidth,
                cornerRadius: appearance.radius, gap: appearance.gap, areaPadding: panel.areaPadding),
            chrome: chrome, text: text, accent: appearance.accent,
            terminal: TerminalAppearance(
                fontFamily: appearance.fontFamily, fontSize: appearance.fontSize, lineHeight: terminal.lineHeight,
                foreground: terminal.foreground, cursor: appearance.accent, palette: terminal.palette,
                paddingX: terminal.paddingX, paddingY: terminal.paddingY),
            strip: strip, header: header, kbd: kbd, statusBar: statusBar,
            focus: focus.following(appearance.accent), palette: palette.following(appearance.accent),
            motion: motion, emptyState: emptyState, resume: resume, agent: agent, observatory: observatory)
    }
}

/// Observatorio.dc.html: cards, the sessions table, the activity chart and the system curves.
public struct ObservatoryTokens: Equatable, Sendable {
    public let stripTitleSize: Double
    public let stripSubtitleSize: Double
    public let stripGap: Double
    public let stripPaddingLeading: Double
    public let stripPaddingTrailing: Double
    public let pillHeight: Double
    public let pillPadding: Double
    public let pillRadius: Double
    public let pillFontSize: Double
    public let pillBorder: RGBAColor
    public let pillText: RGBAColor
    public let padding: Double
    public let gap: Double
    public let sideColumnWidth: Double
    public let cardGap: Double
    public let cardBackground: RGBAColor
    public let cardBorder: RGBAColor
    public let cardRadius: Double
    public let cardPaddingVertical: Double
    public let cardPaddingHorizontal: Double
    public let labelSize: Double
    public let labelTracking: Double
    public let valueSize: Double
    public let noteSize: Double
    public let tableHeaderHeight: Double
    public let rowHeight: Double
    public let rowFontSize: Double
    public let rowBorder: RGBAColor
    public let cellPadding: Double
    /// Column widths in points; nil columns share the rest (`minmax(0, 1.3fr)` twice).
    public let columns: [Double?]
    public let tableDot: Double
    public let contextBarWidth: Double
    public let activityFontSize: Double
    public let activityRowGap: Double
    public let activityTimeWidth: Double
    public let activityToolWidth: Double
    public let chartHeight: Double
    public let chartLineWidth: Double
    public let chartPeakRadius: Double
    public let chartGrid: RGBAColor
    public let chartGridFaint: RGBAColor
    public let sparklineHeight: Double
    public let sparklineWidth: Double
    public let cpu: RGBAColor
    public let gpu: RGBAColor
    public let memoryModel: RGBAColor
    public let memoryRest: RGBAColor
    public let memoryTrack: RGBAColor
    public let memoryBarHeight: Double
    public let separator: RGBAColor
    public let footnoteSize: Double
    public let modelNameSize: Double
    public let systemRowSize: Double
    /// Fade in and out, unless "Reducir movimiento".
    public let fadeDuration: Double
}
