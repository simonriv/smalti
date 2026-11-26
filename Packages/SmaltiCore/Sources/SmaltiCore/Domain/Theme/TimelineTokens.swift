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
