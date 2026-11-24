/// The image preview card of `Main.dc.html` (spec F5.5): sizes from the board; colors from the theme, sharing the
/// completion menu's surface, the key caps' hairline and text, and the palette's shadow.
public struct PreviewCardTokens: Equatable, Sendable {
    public let width = 210.0
    public let cornerRadius = 10.0
    public let padding = 8.0
    public let gap = 6.0
    public let imageSize = Size(width: 194, height: 104)
    public let imageCornerRadius = 6.0
    public let captionFontSize = 10.5
    public let shadowRadius = 40.0
    public let shadowOffsetY = 18.0
    /// The board's `rgba(18,20,27,0.92)`: the completion menu's color, a little more transparent.
    static let backgroundAlpha = 0.92

    public let background: RGBAColor
    public let border: RGBAColor
    public let caption: RGBAColor
    public let shadowOpacity: Double
    public let appearDuration: Double

    init(theme: Theme) {
        background = theme.inputMenu.background.withAlpha(Self.backgroundAlpha)
        border = theme.kbd.border
        caption = theme.kbd.text
        shadowOpacity = theme.palette.shadowOpacity
        appearDuration = theme.motion.overlayAppearDuration
    }
}

extension Theme {
    public var previewCard: PreviewCardTokens { PreviewCardTokens(theme: self) }
}
