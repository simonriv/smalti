import AppKit
import SmaltiCore

/// The search bar of mockup-search.png: the palette's glass box, 340 × 36, with the field, "n de m" and the keys.
@MainActor
final class SearchBarView: NSView {
    static let size = NSSize(width: 340, height: 36)

    let field = PaletteField()
    private let counter = NSTextField(labelWithString: "")
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: content(), theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Buscar en el panel")
        setAccessibilityIdentifier("smalti.search")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    /// "2 de 3", "Sin resultados", or nothing before the first count.
    func showCount(_ text: String) {
        counter.stringValue = text
        counter.setAccessibilityValue(text)
    }

    private func content() -> NSView {
        let palette = theme.palette
        let icon = CommandIconView(CommandIcons.search, size: palette.iconSize, lineWidth: palette.searchIconStroke)
        icon.color = theme.text.secondary.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.rowFontSize)
        field.textColor = theme.text.title.nsColor
        field.placeholderString = "Buscar en el panel"
        field.setAccessibilityLabel("Buscar en el panel")
        field.setAccessibilityIdentifier("smalti.searchField")
        counter.font = theme.interfaceFont(size: palette.footerFontSize)
        counter.textColor = theme.text.secondary.nsColor
        counter.setAccessibilityIdentifier("smalti.searchCount")
        counter.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [
            icon, field, counter, KbdView("↑", theme: theme), KbdView("↓", theme: theme), KbdView("esc", theme: theme),
        ])
        row.spacing = palette.fieldGap / 2
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldGap, bottom: 0, right: palette.fieldGap)
        return row
    }
}
