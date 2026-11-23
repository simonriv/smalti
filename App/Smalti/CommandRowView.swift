import AppKit
import SmaltiCore

/// A palette group label: uppercase, 10.5 pt, 0.06 em tracking, secondary color.
@MainActor
final class CommandGroupLabel: NSView {
    init(_ group: CommandGroup, theme: Theme) {
        super.init(frame: .zero)
        let palette = theme.palette
        let font = theme.interfaceFont(size: palette.groupFontSize)
        let label = NSTextField(
            labelWithAttributedString: NSAttributedString(
                string: group.rawValue.uppercased(),
                attributes: [
                    .font: font, .foregroundColor: theme.text.secondary.nsColor,
                    .kern: palette.groupTracking * palette.groupFontSize,
                ]))
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: palette.groupPaddingHorizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: palette.groupPaddingTop),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -palette.groupPaddingBottom),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}

/// A palette row (38 pt): icon, title with its subtitle after an em dash, and "actual" or the shortcut on the right.
@MainActor
final class CommandRowView: NSView {
    let command: Command
    var onClick: (() -> Void)?
    private let icon: CommandIconView
    private let title = NSTextField(labelWithString: "")
    private let theme: Theme

    init(_ command: Command, theme: Theme) {
        self.command = command
        self.theme = theme
        icon = CommandIconView(
            command.icon.map(CommandIcons.path(for:)), size: theme.palette.iconSize,
            lineWidth: theme.palette.commandIconStroke)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.palette.rowCornerRadius
        layoutRow()
        setSelected(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.paletteRow")
        setAccessibilityLabel(command.title)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func setSelected(_ isSelected: Bool) {
        let palette = theme.palette
        layer?.backgroundColor = isSelected ? palette.selection.nsColor.cgColor : NSColor.clear.cgColor
        icon.color = (isSelected ? theme.accent : theme.text.secondary).nsColor
        title.attributedStringValue = titleText(color: isSelected ? theme.text.title : theme.text.primary)
        setAccessibilityValue(isSelected ? "selected" : nil)
    }

    /// Like a button: the command runs when the click ends inside the row.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    private func layoutRow() {
        let palette = theme.palette
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [icon, title, spacer, trailingView()])
        row.spacing = palette.rowGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: palette.rowHeight),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: palette.rowPadding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -palette.rowPadding),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// "Layout: Dwindle — cada panel nuevo divide el último", the subtitle in the secondary color.
    private func titleText(color: RGBAColor) -> NSAttributedString {
        let font = theme.interfaceFont(size: theme.palette.rowFontSize)
        let text = NSMutableAttributedString(
            string: command.title, attributes: [.font: font, .foregroundColor: color.nsColor])
        if let subtitle = command.subtitle {
            text.append(
                NSAttributedString(
                    string: " — \(subtitle)", attributes: [.font: font, .foregroundColor: theme.text.secondary.nsColor])
            )
        }
        return text
    }

    /// The current layout says "actual" in the accent; other commands show their shortcut.
    private func trailingView() -> NSView {
        guard command.isCurrent else { return KbdView(command.shortcut?.display ?? "", theme: theme) }
        let marker = NSTextField(labelWithString: "actual")
        marker.font = theme.interfaceFont(size: theme.palette.markerFontSize)
        marker.textColor = theme.accent.nsColor
        return marker
    }
}
