/// F9's timeline (no board draws it; `docs/specs/F9-assets/mockup.html`): a 480 pt panel on the right of the panes,
/// with the observatory's chips and key footer, prompts marked by the accent's edge, tools in mono cyan and the app's
/// state code for their status.
public struct TimelineTokens: Equatable, Sendable {
    public let width = 480.0
    public let margin = 10.0
    public let radius = 12.0
    public let headerHeight: Double
    public let footerHeight = 30.0
    public let padding = 14.0
    public let itemPaddingVertical = 7.0
    public let itemPaddingLeading = 16.0
    public let toolRowHeight = 24.0
    public let childIndent = 18.0
    public let promptEdgeWidth = 2.0
    public let promptEdgeGap = 9.0
    public let selectionEdgeWidth = 2.0
    public let whoFontSize = 10.5
    public let textFontSize = 12.5
    public let monoFontSize = 11.5
    public let sessionTitleSize = 13.0
    public let sessionLineSize = 11.5
    public let promptLines = 3
    public let replyLines = 4
    public let outputRadius = 7.0
    public let outputPadding = 9.0
    public let searchFieldHeight = 26.0
    public let snippetWidth = 120
    public let noticeSeconds = 4.0
    public let emptyTitleSize = 14.0
    public let emptyBodySize = 12.0
    public let recentRowHeight = 34.0
    public let fadeOffset = 8.0
    /// "Leyendo…" shows only when a read takes longer (spec §3).
    public let loadingDelayMilliseconds = 150
    public let smallFontSize = 11.0
    public let groupTitleSize = 11.5
    public let bannerFontSize = 11.5
    public let hitFontSize = 12.0
    public let recentFontSize = 12.0
    public let chevronSize = 10.0
    public let titleWeight = 600
    public let mediumWeight = 500
    public let emptyDotSize = 10.0
    public let emptyTitleLines = 3
    public let emptyBodyLines = 6
    public let shadowRadius = 25.0
    public let shadowOffsetX = -18.0
    public let headerGap = 8.0
    public let headerTrailing = 12.0
    public let chipPadding = 8.0
    public let topSpacing = 6.0
    public let topPaddingVertical = 9.0
    public let bannerRadius = 8.0
    public let bannerPaddingVertical = 8.0
    public let bannerPaddingHorizontal = 10.0
    public let bannerGap = 8.0
    /// What the banner's dot, gap and padding take from its text's width.
    public let bannerTextInset = 40.0
    public let footerGap = 10.0
    public let footerKeyGap = 5.0
    public let listTop = 6.0
    public let outputPaddingVertical = 7.0
    public let outputBottom = 4.0
    public let notePaddingVertical = 8.0
    public let groupPaddingTop = 9.0
    public let groupPaddingBottom = 4.0
    public let groupGap = 2.0
    public let hitPaddingVertical = 6.0
    public let hitGap = 1.0
    public let hitLines = 2
    public let emptyPaddingTop = 20.0
    public let emptyPaddingHorizontal = 22.0
    public let emptyPaddingBottom = 6.0
    public let emptyGap = 10.0
    public let captionPaddingTop = 14.0
    public let captionPaddingBottom = 4.0
    public let recentGap = 9.0
    public let recentIndent = 6.0
    public let whoGap = 8.0
    public let statusGap = 5.0
    public let toolGap = 8.0
    public let textGap = 3.0
    public let outputGap = 3.0
    /// What a row's padding and scroller take from the width its text wraps to.
    public let textWidthInset = 20.0
    public let outputWidthInset = 80.0
    public let guideWidth = 1.0
    public let searchGlyphGap = 7.0

    public let surface: RGBAColor
    public let border: RGBAColor
    public let shadowOpacity = 0.38
    public let promptEdge: RGBAColor
    public let toolName: RGBAColor
    public let outputBackground: RGBAColor
    public let guide: RGBAColor
    public let matchHighlight: RGBAColor
    public let unidentifiedDot: RGBAColor
    public let bannerBackground: RGBAColor
    public let failure: RGBAColor
    private let done: RGBAColor
    private let failed: RGBAColor
    /// ANSI 6: the mockup's tool names.
    private static let cyan = 6

    init(theme: Theme) {
        headerHeight = theme.chrome.topStripHeight
        surface = theme.window.background.withAlpha(0.90)
        border = theme.window.border
        promptEdge = theme.accent.withAlpha(0.55)
        toolName = theme.terminal.palette.indices.contains(Self.cyan) ? theme.terminal.palette[Self.cyan] : theme.accent
        outputBackground = theme.kbd.background
        guide = theme.observatory.pillBorder
        matchHighlight = theme.accent.withAlpha(0.28)
        unidentifiedDot = theme.agent.waiting
        bannerBackground = theme.kbd.background
        failure = theme.agent.failed
        done = theme.agent.working
        failed = theme.agent.failed
    }

    /// ✓ and the working dot in the working green, a failure in the error red.
    public func color(for status: ToolStatus) -> RGBAColor {
        switch status {
        case .working, .done: done
        case .failed: failed
        }
    }
}

extension Theme {
    public var timeline: TimelineTokens { TimelineTokens(theme: self) }
}
