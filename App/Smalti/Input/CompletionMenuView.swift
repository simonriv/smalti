import AppKit
import SmaltiCore

/// The Tab menu of `Main.dc.html`: up to eight rows (name in the terminal font, description in Inter, secondary
/// color), the selected one on the accent's selection glow, and the help line underneath.
@MainActor
final class CompletionMenuView: NSView {
    static let help = String(localized: "Tab complete · → accept suggestion · ⌃R history")

    private let theme: Theme
    private var rows: [NSView] = []
    private let footer: NSTextField

    init(theme: Theme) {
        self.theme = theme
        footer = NSTextField(labelWithString: Self.help)
        super.init(frame: .zero)
        let tokens = theme.inputMenu
        wantsLayer = true
        layer?.backgroundColor = tokens.background.nsColor.cgColor
        layer?.cornerRadius = tokens.cornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = tokens.border.nsColor.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(tokens.shadowOpacity)
        layer?.shadowRadius = tokens.shadowRadius / 2
        layer?.shadowOffset = CGSize(width: 0, height: -tokens.shadowOffsetY)
        footer.font = theme.interfaceFont(size: tokens.footerFontSize)
        footer.textColor = theme.text.secondary.nsColor
        footer.setAccessibilityIdentifier("smalti.completionHelp")
        addSubview(footer)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityIdentifier("smalti.completionMenu")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Shows the rows around `selected`, at most `maximumVisibleRows`.
    func show(_ items: [Suggestion], selected: Int) {
        rows.forEach { $0.removeFromSuperview() }
        let tokens = theme.inputMenu
        let visible = min(items.count, tokens.maximumVisibleRows)
        let first = max(0, min(selected - visible + 1, items.count - visible))
        rows = items.indices.dropFirst(first).prefix(visible).enumerated().map { offset, index in
            let row = row(for: items[index], isSelected: index == selected)
            row.frame = NSRect(
                x: tokens.padding, y: tokens.padding + Double(offset) * (tokens.rowHeight + tokens.rowGap),
                width: bounds.width - 2 * tokens.padding, height: tokens.rowHeight)
            addSubview(row)
            return row
        }
        let rowsHeight = Double(visible) * tokens.rowHeight + Double(max(visible - 1, 0)) * tokens.rowGap
        footer.frame = NSRect(
            x: tokens.padding + tokens.rowPaddingHorizontal, y: tokens.padding + rowsHeight + tokens.footerTopGap,
            width: bounds.width - 2 * (tokens.padding + tokens.rowPaddingHorizontal),
            height: tokens.footerHeight - tokens.footerTopGap)
    }

    private func row(for item: Suggestion, isSelected: Bool) -> NSView {
        let tokens = theme.inputMenu
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = tokens.rowCornerRadius
        // Main.dc.html's `{{glow}}`: the accent at 13 %.
        row.layer?.backgroundColor = isSelected ? theme.focus.glow.nsColor.cgColor : nil
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.row)
        row.setAccessibilityIdentifier("smalti.completionRow")
        row.setAccessibilityLabel(item.name)
        row.setAccessibilitySelected(isSelected)
        let name = NSTextField(labelWithString: item.name)
        name.font = theme.monospacedFont(size: tokens.rowFontSize)
        name.textColor = (isSelected ? theme.text.title : theme.text.primary).nsColor
        name.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: item.description ?? "")
        detail.font = theme.interfaceFont(size: tokens.rowFontSize)
        detail.textColor = theme.text.secondary.nsColor
        detail.lineBreakMode = .byTruncatingTail
        let textHeight = tokens.rowFontSize * tokens.textLineHeight
        let top = (tokens.rowHeight - textHeight) / 2
        name.frame = NSRect(x: tokens.rowPaddingHorizontal, y: top, width: tokens.nameColumnWidth, height: textHeight)
        let detailX = tokens.rowPaddingHorizontal + tokens.nameColumnWidth + tokens.columnGap
        detail.frame = NSRect(
            x: detailX, y: top, width: bounds.width - 2 * tokens.padding - detailX - tokens.rowPaddingHorizontal,
            height: textHeight)
        row.addSubview(name)
        row.addSubview(detail)
        return row
    }
}
