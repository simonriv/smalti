/// The prompt studio (`Prompt.dc.html`): the preview and templates on the left, the 400 px aside on the right. Sizes
/// from the board, colors from the theme; what it shares with Apariencia (cards, segments, labels) comes from
/// `AppearancePanelTokens`.
public struct PromptStudioTokens: Equatable, Sendable {
    public let asideWidth = 400.0
    public let asidePaddingVertical = 22.0
    public let asidePaddingHorizontal = 20.0
    public let asideGap = 16.0
    public let mainPaddingVertical = 24.0
    public let mainPaddingHorizontal = 28.0
    public let mainGap = 18.0
    public let previewCornerRadius = 11.0
    public let previewPaddingVertical = 18.0
    public let previewPaddingHorizontal = 20.0
    public let previewGap = 16.0
    public let previewLabelGap = 6.0
    public let previewFontSize = 13.0
    public let templateGap = 10.0
    public let templatePadding = 12.0
    public let templateFontSize = 11.5
    public let moduleRowHeight = 38.0
    public let moduleRowGap = 2.0
    public let moduleRowPadding = 10.0
    public let moduleRowCornerRadius = 8.0
    public let moduleRowInnerGap = 10.0
    public let checkboxSize = 16.0
    public let buttonHeight = 34.0
    public let buttonPadding = 14.0
    public let buttonCornerRadius = 8.0
    public let buttonGap = 10.0
    public let gridGap = 12.0
    public let gridInnerGap = 6.0
    public let sectionInnerGap = 8.0
    public let noteGap = 4.0
    public let separatorHeight = 1.0

    public let previewBackground: RGBAColor
    public let previewBorder: RGBAColor
    public let separator: RGBAColor
    public let activeRow: RGBAColor
    public let handle: RGBAColor
    public let applyBackground: RGBAColor
    public let applyText: RGBAColor
    public let exportBorder: RGBAColor
    public let exportText: RGBAColor

    init(theme: Theme) {
        let line = theme.panel.border
        previewBackground = theme.panel.background.withAlpha(0.38)
        previewBorder = line
        separator = line.withAlpha(0.05)
        activeRow = line.withAlpha(0.03)
        handle = theme.agent.stopped
        applyBackground = theme.accent
        applyText = theme.resume.primaryButtonText
        exportBorder = line.withAlpha(0.12)
        exportText = theme.text.primary
    }
}

extension Theme {
    public var promptStudio: PromptStudioTokens { PromptStudioTokens(theme: self) }
}
