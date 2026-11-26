/// F8's processes and ports views (no board draws them; `docs/specs/F8-assets/mockup.html`): the observatory's strip,
/// cards and table, with their own columns, a filter field, a key footer and the approval card's amber surface to
/// confirm forcing a process to quit.
public struct ProcessesTokens: Equatable, Sendable {
    public let rowHeight = 36.0
    /// Estado · Proceso · Panel · CPU · Memoria · PID; nil shares the rest.
    public let processColumns: [Double?] = [128, nil, 120, 118, 86, 70]
    /// Puerto · Protocolo · Dirección · Proceso · PID · Directorio · Panel.
    public let portColumns: [Double?] = [84, 104, 104, nil, 70, nil, 96]
    public let cpuBarWidth = 46.0
    public let cpuBarGap = 8.0
    public let commandGap = 8.0
    public let commandFontSize = 11.5
    public let filterWidth = 210.0
    public let filterHeight = 26.0
    public let filterRadius = 7.0
    public let filterPadding = 9.0
    public let filterFontSize = 12.0
    public let footerHeight = 30.0
    public let footerPadding = 18.0
    public let footerGap = 16.0
    public let footerKeyGap = 6.0
    public let footerFontSize = 11.5
    public let tagFontSize = 10.5
    public let tagRadius = 4.0
    public let tagPadding = 4.0
    public let tagGap = 6.0
    public let detailKeyWidth = 96.0
    public let detailRowGap = 7.0
    public let detailFontSize = 12.0
    public let actionHeight = 24.0
    public let actionKeyWidth = 34.0
    public let commandBlockRadius = 7.0
    public let commandBlockPadding = 8.0
    public let confirmWidth = 520.0
    public let confirmBottom = 58.0
    public let confirmPadding = 14.0
    public let confirmGap = 8.0
    public let confirmTitleSize = 13.0
    public let confirmBodySize = 12.0
    public let actionGap = 10.0
    public let summaryGap = 10.0
    public let commandBlockLines = 4
    public let filterGlyphSize = 12.0
    /// How long a notice (protected, gone, lowered) stays in the footer.
    public let noticeSeconds = 4.0
    /// CPU values kept for the "Your processes" line: two minutes at one refresh every 2 s.
    public let cpuHistoryLength = 60

    public let treeGuide: RGBAColor
    public let tagBorder: RGBAColor
    public let filterBorder: RGBAColor
    public let filterBackground: RGBAColor
    public let placeholder: RGBAColor
    public let commandBlock: RGBAColor
    public let contextText: RGBAColor
    public let panesMemory: RGBAColor
    public let restMemory: RGBAColor
    public let notice: RGBAColor
    public let failure: RGBAColor
    /// The 28 % shade behind the confirmation to force.
    public let shade: RGBAColor

    init(theme: Theme) {
        treeGuide = theme.agent.stopped
        tagBorder = theme.observatory.pillBorder
        filterBorder = theme.observatory.pillBorder
        filterBackground = theme.kbd.background
        placeholder = theme.text.secondary
        commandBlock = theme.kbd.background
        contextText = theme.text.secondary
        panesMemory = theme.accent
        restMemory = theme.observatory.memoryRest
        notice = theme.text.secondary
        failure = theme.agent.failed
        shade = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    }
}

extension Theme {
    public var processes: ProcessesTokens { ProcessesTokens(theme: self) }

    /// The app-wide state code: green active, hollow idle or stopped, amber not responding, red zombie.
    public func statusDot(for state: ProcessState) -> StatusDotStyle {
        switch state {
        case .active: .filled(agent.working)
        case .idle, .stopped: .hollow(agent.stopped, width: agent.stoppedRingWidth)
        case .unresponsive: .filled(agent.waiting)
        case .zombie: .filled(agent.failed)
        }
    }

    /// The state's words take its color, except the quiet ones, which take the secondary text (as in the boards).
    public func stateTextColor(for state: ProcessState) -> RGBAColor {
        switch state {
        case .active: agent.working
        case .idle, .stopped: text.secondary
        case .unresponsive: agent.waiting
        case .zombie: agent.failed
        }
    }
}
