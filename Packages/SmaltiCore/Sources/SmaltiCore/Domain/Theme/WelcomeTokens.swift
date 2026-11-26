/// F7.7: the welcome card (no board draws it): the ⌘K glass box of "Reportar un problema o una idea" at 560 pt, with
/// the palette's rows and footer. Everything but the width comes from tokens that already exist.
public struct WelcomeTokens: Equatable, Sendable {
    public static let cardWidth = 560.0

    public let width: Double
    public let topOffset: Double
    public let padding: Double
    public let titleFontSize: Double
    public let subtitleFontSize: Double
    public let rowHeight: Double
    public let rowFontSize: Double
    public let lineGap: Double
    public let shortcutGap: Double
}

extension Theme {
    public var welcome: WelcomeTokens {
        WelcomeTokens(
            width: WelcomeTokens.cardWidth, topOffset: feedback.topOffset, padding: feedback.padding,
            titleFontSize: feedback.titleFontSize, subtitleFontSize: feedback.noteFontSize,
            rowHeight: feedback.choiceHeight, rowFontSize: palette.rowFontSize, lineGap: feedback.lineGap,
            shortcutGap: feedback.dotGap)
    }
}
