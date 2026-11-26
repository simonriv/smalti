import AppKit
import SmaltiCore

/// F8.5, ⌘O (mockup `recent`): the ⌘K glass with "Buscar proyecto", the "Proyectos" group and one 48 pt row per
/// project (name, path in mono, and "abierto · workspace N" in the accent or when it was last opened). The rows and
/// the selection come from the domain (`ProjectSelector`); the controller drives the keys.
@MainActor
final class RecentProjectsView: NSView {
    let field = NSTextField()
    var onClickRow: ((Int) -> Void)?
    private let theme: Theme
    private let list = NSStackView()
    private let texts = ProjectTexts.current

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: content(), theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(texts.projects)
        setAccessibilityIdentifier("smalti.projects")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    func render(_ selector: ProjectSelector) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !selector.rows.isEmpty else {
            list.addArrangedSubview(empty(selector.emptyText))
            return
        }
        list.addArrangedSubview(
            CommandGroupLabel(text: texts.projects, theme: theme, identifier: "smalti.paletteGroup"))
        for (index, row) in selector.rows.enumerated() {
            let view = ProjectRowView(row, isSelected: index == selector.selected, theme: theme)
            view.onClick = { [weak self] in self?.onClickRow?(index) }
            list.addArrangedSubview(view)
        }
    }

    private func content() -> NSView {
        let palette = theme.palette
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(
            top: palette.listPaddingTop, left: palette.listPaddingHorizontal, bottom: palette.listPaddingBottom,
            right: palette.listPaddingHorizontal)
        let stack = NSStackView(views: [
            fieldRow(), OverlayBox.separator(theme: theme), list, OverlayBox.separator(theme: theme), footer(),
        ])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.widthAnchor.constraint(equalToConstant: theme.projects.selectorWidth).isActive = true
        return stack
    }

    private func fieldRow() -> NSView {
        let palette = theme.palette
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.fieldFontSize)
        field.textColor = theme.text.title.nsColor
        field.placeholderAttributedString = NSAttributedString(
            string: texts.searchPlaceholder,
            attributes: [
                .font: theme.interfaceFont(size: palette.fieldFontSize), .foregroundColor: theme.text.secondary.nsColor,
            ])
        field.setAccessibilityLabel(texts.searchPlaceholder)
        field.setAccessibilityIdentifier("smalti.projects.filter")
        let icon = CommandIconView(
            CommandIcons.path(for: .recentProjects), size: palette.iconSize, lineWidth: palette.searchIconStroke)
        icon.color = theme.text.secondary.nsColor
        let row = NSStackView(views: [icon, field, KbdView("esc", theme: theme)])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func footer() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let pitch = OverlayBox.footerLabel(texts.dropsOff, theme: theme)
        let row = NSStackView(views: [
            OverlayBox.hint("↑↓", texts.choose, theme: theme), OverlayBox.hint("↵", texts.openOrGo, theme: theme),
            OverlayBox.hint("⌘O", texts.next, theme: theme), OverlayBox.hint("esc", texts.close, theme: theme),
            spacer, pitch,
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }

    private func empty(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = theme.interfaceFont(size: theme.palette.rowFontSize)
        label.textColor = theme.text.secondary.nsColor
        label.setAccessibilityIdentifier("smalti.projects.empty")
        let box = NSStackView(views: [label])
        box.edgeInsets = NSEdgeInsets(
            top: theme.palette.rowPadding, left: theme.palette.rowPadding, bottom: theme.palette.rowPadding,
            right: theme.palette.rowPadding)
        return box
    }
}

/// One project of the selector: folder icon, name over its path, and where it is open or when it was opened.
@MainActor
private final class ProjectRowView: NSView {
    var onClick: (() -> Void)?

    init(_ row: ProjectSelectorRow, isSelected: Bool, theme: Theme) {
        super.init(frame: .zero)
        let palette = theme.palette
        wantsLayer = true
        layer?.cornerRadius = palette.rowCornerRadius
        layer?.backgroundColor = isSelected ? palette.selection.nsColor.cgColor : NSColor.clear.cgColor
        let icon = CommandIconView(
            CommandIcons.path(for: .projectFolder), size: palette.iconSize, lineWidth: palette.commandIconStroke)
        icon.color = (isSelected ? theme.accent : theme.text.secondary).nsColor
        let name = NSTextField(labelWithString: row.name)
        name.font = theme.interfaceFont(size: palette.rowFontSize)
        name.textColor = theme.text.title.nsColor
        let path = NSTextField(labelWithString: row.path)
        path.font = NSFont.monospacedSystemFont(ofSize: theme.projects.pathFontSize, weight: .regular)
        path.textColor = theme.text.secondary.nsColor
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let names = NSStackView(views: [name, path])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = theme.projects.nameGap
        let detail = NSTextField(labelWithString: row.detail)
        detail.font = theme.interfaceFont(size: palette.footerFontSize)
        detail.textColor = (row.isOpen ? theme.accent : theme.text.secondary).nsColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let line = NSStackView(views: [icon, names, spacer, detail])
        line.spacing = palette.rowGap
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: theme.projects.rowHeight),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: palette.rowPadding),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -palette.rowPadding),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.projects.row")
        setAccessibilityLabel(row.name)
        setAccessibilityValue(isSelected ? "selected" : nil)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
