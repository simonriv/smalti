/// The session search of `Reanudar.dc.html` (right column, F6): its sizes, and colors taken from the theme's own.
public struct SessionSearchTokens: Equatable, Sendable {
    public let width: Double = 420
    public let paddingVertical: Double = 24
    public let paddingHorizontal: Double = 20
    public let gap: Double = 14
    public let headerGap: Double = 4
    public let subtitleFontSize: Double = 11.5
    public let fieldHeight: Double = 34
    public let fieldCornerRadius: Double = 8
    public let fieldPadding: Double = 10
    public let fieldGap: Double = 8
    public let fieldFontSize: Double = 12.5
    public let fieldIconSize: Double = 14
    public let chipGap: Double = 6
    public let chipFontSize: Double = 10.5
    public let chipWeight = 500
    public let chipPaddingVertical: Double = 2
    public let chipPaddingHorizontal: Double = 7
    /// The accent behind the chosen chip, at this alpha.
    public let chipSelectedAlpha: Double = 0.18
    public let rowGap: Double = 4
    public let rowPaddingVertical: Double = 10
    public let rowPaddingHorizontal: Double = 12
    public let rowCornerRadius: Double = 9
    public let rowLineGap: Double = 4
    public let rowTitleFontSize: Double = 12.5
    public let rowDetailFontSize: Double = 11.5
    public let footerFontSize: Double = 11.5
    public let footerLineHeight: Double = 1.5
    /// The standalone card (⌘⇧O): the column's content on the ⌘K glass, this tall.
    public let cardHeight: Double = 560

    public let background: RGBAColor
    public let border: RGBAColor
    public let fieldBorder: RGBAColor
    public let fieldBackground: RGBAColor
    public let chipBackground: RGBAColor
    public let chipText: RGBAColor
    public let selectedText: RGBAColor
    public let rowSelected: RGBAColor
    public let secondaryText: RGBAColor

    init(theme: Theme) {
        let line = { (alpha: Double) in theme.panel.border.withAlpha(alpha) }
        background = theme.panel.background.withAlpha(0.55)
        border = theme.panel.border
        fieldBorder = line(0.09)
        fieldBackground = line(0.03)
        chipBackground = line(0.05)
        chipText = theme.kbd.text
        selectedText = theme.text.title
        rowSelected = line(0.03)
        secondaryText = theme.text.secondary
    }
}

extension Theme {
    public var sessionSearch: SessionSearchTokens { SessionSearchTokens(theme: self) }
}
