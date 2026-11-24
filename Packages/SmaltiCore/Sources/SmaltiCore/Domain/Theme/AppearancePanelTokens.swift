/// The Appearance panel (`Apariencia.dc.html`, the 440 px aside): sizes from the board, colors from the theme.
public struct AppearancePanelTokens: Equatable, Sendable {
    public let width = 440.0
    public let paddingVertical = 22.0
    public let paddingHorizontal = 24.0
    public let sectionGap = 22.0
    /// Between a section's label and its content.
    public let labelGap = 10.0
    public let titleFontSize = 16.0
    public let noteFontSize = 11.5
    public let labelFontSize = 10.5
    /// `letter-spacing: .06em` of the uppercase labels.
    public let labelTracking = 0.06
    public let rowFontSize = 12.5
    public let rowGap = 14.0
    public let cardGap = 10.0
    public let cardCornerRadius = 10.0
    public let cardPadding = 8.0
    public let cardSelectedBorderWidth = 1.5
    public let cardBorderWidth = 1.0
    public let previewHeight = 54.0
    public let previewCornerRadius = 6.0
    public let previewBarHeight = 4.0
    public let previewBarGap = 5.0
    /// Widths of the three preview bars, as fractions of the preview.
    public let previewBarWidths = [0.6, 0.8, 0.45]
    public let swatchSize = 22.0
    public let swatchCornerRadius = 6.0
    public let swatchGap = 8.0
    public let segmentHeight = 30.0
    public let segmentCornerRadius = 7.0
    public let segmentContainerPadding = 3.0
    public let segmentContainerCornerRadius = 9.0
    public let segmentFontSize = 12.0
    public let checkboxSize = 18.0
    /// Between a card's preview and its name (`gap: 7px`).
    public let cardInnerGap = 7.0
    /// Above the note under "Proteger legibilidad" (`margin-top: 2px`).
    public let noteGap = 2.0
    /// Between a slider's title row and the slider (`gap: 6px`).
    public let sliderGap = 6.0
    /// Between a footer label and its value (`gap: 4px`).
    public let footerGap = 4.0
    /// Between a value and its stepper (not on the board: the steppers are Smalti's).
    public let stepperGap = 4.0
    /// Least space between a segment's text and its edges.
    public let segmentLabelInset = 4.0
    public let segmentContainerBorderWidth = 1.0
    /// The aside's left border (`border-left: 1px`).
    public let borderWidth = 1.0

    public let title: RGBAColor
    public let text: RGBAColor
    public let secondary: RGBAColor
    public let muted: RGBAColor
    public let border: RGBAColor
    public let cardBorder: RGBAColor
    public let selectedCardBorder: RGBAColor
    public let selectedCardBackground: RGBAColor
    public let segmentContainer: RGBAColor
    public let segmentContainerBorder: RGBAColor
    public let selectedSegment: RGBAColor
    private let tint: RGBAColor

    /// The board's `rgba(10,11,16,0.55)`: the theme's panel color, raised like the chrome when protection needs it.
    public func background(protectedAt chromeOpacity: Double) -> RGBAColor {
        tint.withAlpha(max(Self.boardBackgroundOpacity, chromeOpacity))
    }

    private static let boardBackgroundOpacity = 0.55

    init(theme: Theme) {
        let line = theme.panel.border
        title = theme.text.title
        text = theme.text.primary
        secondary = theme.text.secondary
        muted = theme.strip.inactiveText
        border = line
        cardBorder = line.withAlpha(0.08)
        selectedCardBorder = theme.accent
        selectedCardBackground = theme.accent.withAlpha(0.08)
        segmentContainer = line.withAlpha(0.04)
        segmentContainerBorder = line.withAlpha(0.06)
        selectedSegment = theme.accent.withAlpha(0.18)
        tint = theme.panel.background.withAlpha(1)
    }
}

extension Theme {
    public var appearancePanel: AppearancePanelTokens { AppearancePanelTokens(theme: self) }
}
