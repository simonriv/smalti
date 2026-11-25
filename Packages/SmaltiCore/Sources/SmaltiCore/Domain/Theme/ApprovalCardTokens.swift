/// The approval card of F7.5 (no board draws it): the preview card's surface (F5.5) with the amber of "te espera"
/// around it and on its dot. «PROD» goes in bold, never in a new color.
public struct ApprovalCardTokens: Equatable, Sendable {
    public let maximumWidth = 560.0
    public let margin = 12.0
    public let padding = 12.0
    public let gap = 8.0
    public let dotSize = 8.0
    public let titleFontSize = 12.5
    public let bodyFontSize = 11.5
    public let commandFontSize = 11.5
    public let footerFontSize = 10.5
    public let commandPadding = 8.0
    public let commandCornerRadius = 6.0
    public let maximumCommandLines = 8

    public let cornerRadius: Double
    public let background: RGBAColor
    public let border: RGBAColor
    public let dot: RGBAColor
    public let title: RGBAColor
    public let body: RGBAColor
    public let commandBackground: RGBAColor
    public let shadowOpacity: Double
    public let shadowRadius: Double
    public let shadowOffsetY: Double
    public let appearDuration: Double

    init(theme: Theme) {
        let preview = theme.previewCard
        cornerRadius = preview.cornerRadius
        background = preview.background
        border = theme.agent.waitingBorder
        dot = theme.agent.waiting
        title = theme.statusBar.text
        body = preview.caption
        commandBackground = theme.kbd.background
        shadowOpacity = preview.shadowOpacity
        shadowRadius = preview.shadowRadius
        shadowOffsetY = preview.shadowOffsetY
        appearDuration = preview.appearDuration
    }
}

extension Theme {
    public var approvalCard: ApprovalCardTokens { ApprovalCardTokens(theme: self) }
}
