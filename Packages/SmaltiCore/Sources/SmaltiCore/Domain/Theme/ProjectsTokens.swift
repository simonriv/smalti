/// F8.5 (mockup `recent`, `confirm`, `changed`, `replace`): the ⌘K glass for the ⌘O selector and the project cards,
/// with the amber border of a decision (F7.5) and the 28 % shade behind a card.
public struct ProjectsTokens: Equatable, Sendable {
    public let selectorWidth = 600.0
    public let confirmWidth = 600.0
    /// Distance from the top of the window: the mockup's card at 200 px on the desk, 40 px below its top.
    public let confirmTopOffset = 160.0
    /// The selector's two-line rows.
    public let rowHeight = 48.0
    public let nameGap = 2.0
    public let pathFontSize = 11.5
    public let padding = 18.0
    public let titleFontSize = 15.0
    public let bodyFontSize = 12.5
    public let noteFontSize = 11.5
    public let headingGap = 6.0
    public let lineGap = 8.0
    public let dotGap = 9.0
    public let commandsPadding = 8.0
    public let commandsRadius = 9.0
    public let commandRowHeight = 28.0
    public let commandFontSize = 12.5
    public let signWidth = 22.0
    public let confirmBorder: RGBAColor
    public let commandsBackground: RGBAColor
    /// The red line through a removed command.
    public let removedStrike: RGBAColor
    public let shade: RGBAColor

    init(theme: Theme) {
        confirmBorder = theme.agent.waiting.withAlpha(0.55)
        commandsBackground = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.22)
        removedStrike = theme.agent.failed.withAlpha(0.6)
        shade = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    }
}

extension Theme {
    public var projects: ProjectsTokens { ProjectsTokens(theme: self) }
}
