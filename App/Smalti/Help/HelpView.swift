import AppKit
import SmaltiCore

/// The help of mockup-help.png: the ⌘K box at 760 pt, a search field, two columns of sections and a footer. It draws;
/// `HelpController` decides.
@MainActor
final class HelpView: NSView {
    let field = PaletteField()
    var onClickEntry: ((Int) -> Void)?
    private let theme: Theme
    private let columns = NSStackView()
    private let scroll = NSScrollView()
    private var scrollHeight: NSLayoutConstraint?
    private var rows: [HelpRowView] = []

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let stack = NSStackView(views: [fieldRow(), OverlayBox.separator(theme: theme), listArea(), footerArea()])
        stack.orientation = .vertical
        stack.spacing = 0
        OverlayBox.decorate(self, around: stack, theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Ayuda de Smalti")
        setAccessibilityIdentifier("smalti.help")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    /// Two columns, balanced by rows; `selected` indexes the entries in reading order (left column first).
    func show(_ sections: [HelpSection], selected: Int, maximumListHeight: Double) {
        rows = []
        let split = Self.balancedSplit(sections)
        let views = [Array(sections[..<split]), Array(sections[split...])].map(column)
        columns.setViews(views, in: .leading)
        highlight(selected)
        columns.layoutSubtreeIfNeeded()
        scrollHeight?.constant = min(columns.fittingSize.height, maximumListHeight)
    }

    func highlight(_ selected: Int) {
        for (index, row) in rows.enumerated() { row.setSelected(index == selected) }
        if rows.indices.contains(selected) {
            let row = rows[selected]
            row.scrollToVisible(row.bounds)
        }
    }

    /// The first index of the right column: where half of the rows have been placed.
    private static func balancedSplit(_ sections: [HelpSection]) -> Int {
        let total = sections.reduce(0) { $0 + $1.entries.count + 1 }
        var placed = 0
        for (index, section) in sections.enumerated() {
            placed += section.entries.count + 1
            if placed * 2 >= total { return index + 1 }
        }
        return sections.count
    }

    private func column(_ sections: [HelpSection]) -> NSView {
        var views: [NSView] = []
        for section in sections {
            views.append(CommandGroupLabel(text: section.title, theme: theme, identifier: "smalti.helpSection"))
            for entry in section.entries {
                let index = rows.count
                let row = HelpRowView(entry, theme: theme)
                row.onClick = { [weak self] in self?.onClickEntry?(index) }
                rows.append(row)
                views.append(row)
            }
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func fieldRow() -> NSView {
        let palette = theme.palette
        let icon = CommandIconView(CommandIcons.search, size: palette.iconSize, lineWidth: palette.searchIconStroke)
        icon.color = theme.text.secondary.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.fieldFontSize)
        field.textColor = theme.text.title.nsColor
        field.placeholderString = "Buscar atajos y acciones"
        field.setAccessibilityLabel("Buscar atajos y acciones")
        field.setAccessibilityIdentifier("smalti.helpField")
        let row = NSStackView(views: [icon, field, KbdView("esc", theme: theme)])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func listArea() -> NSView {
        let palette = theme.palette
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = theme.help.columnGap
        columns.edgeInsets = NSEdgeInsets(
            top: palette.listPaddingTop, left: palette.listPaddingHorizontal, bottom: palette.listPaddingBottom,
            right: palette.listPaddingHorizontal)
        let document = HelpFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        columns.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(columns)
        OverlayBox.pin(columns, to: document)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        scrollHeight?.isActive = true
        return scroll
    }

    /// "Ayuda de Smalti" and the keys that act here (mockup-help.png).
    private func footerArea() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [
            OverlayBox.footerLabel("Ayuda de Smalti", theme: theme), spacer,
            OverlayBox.hint("↩", "ejecutar", theme: theme), OverlayBox.hint("esc", "cerrar", theme: theme),
            OverlayBox.hint("⌘,", "configuración", theme: theme),
            OverlayBox.footerLabel("Reportar un problema", theme: theme),
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        let footer = NSStackView(views: [OverlayBox.separator(theme: theme), row])
        footer.orientation = .vertical
        footer.spacing = 0
        return footer
    }
}

/// One row: what it does, and its keys as a `.kbd` or, for words ("en ⌘K", "arrastrar"), in secondary text.
@MainActor
final class HelpRowView: NSView {
    var onClick: (() -> Void)?
    private let theme: Theme

    private static let wordKeys: Set<String> = ["arrastrar", "clic derecho"]

    init(_ entry: HelpEntry, theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.palette.rowCornerRadius
        let title = NSTextField(labelWithString: entry.title)
        title.font = theme.interfaceFont(size: theme.palette.rowFontSize)
        title.textColor = theme.text.primary.nsColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [title, spacer, keys(entry.keys)])
        row.edgeInsets = NSEdgeInsets(
            top: 0, left: theme.palette.rowPadding, bottom: 0, right: theme.palette.rowPadding)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        OverlayBox.pin(row, to: self)
        heightAnchor.constraint(equalToConstant: theme.help.rowHeight).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(entry.title), \(entry.keys)")
        setAccessibilityIdentifier("smalti.helpRow")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func setSelected(_ isSelected: Bool) {
        layer?.backgroundColor = isSelected ? theme.palette.selection.nsColor.cgColor : NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    private func keys(_ text: String) -> NSView {
        guard text.hasPrefix("en ") || Self.wordKeys.contains(text) else { return KbdView(text, theme: theme) }
        let label = NSTextField(labelWithString: text)
        label.font = theme.interfaceFont(size: theme.palette.footerFontSize)
        label.textColor = theme.text.secondary.nsColor
        return label
    }
}

/// Lays the columns out top-down inside the scroll view.
private final class HelpFlippedView: NSView {
    override var isFlipped: Bool { true }
}
