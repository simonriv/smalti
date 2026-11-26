import AppKit
import SmaltiCore

/// The welcome card (spec F7.7, «Primer arranque»): the ⌘K glass box with the title, seven shortcuts from the keymap,
/// the two integrations and the theme as rows, and the keys. Every action has a key: ↑↓ choose, space installs,
/// ←→ change the theme, ↩ start, esc skip.
@MainActor
final class WelcomeView: NSView {
    var onMove: ((Int) -> Void)?
    var onInstall: (() -> Void)?
    var onCycleTheme: ((Int) -> Void)?
    var onFinish: (() -> Void)?
    var onSkip: (() -> Void)?
    var onChoose: ((WelcomeRow) -> Void)?
    private let theme: Theme
    private let texts: WelcomeTexts
    private var rows: [WelcomeRow: WelcomeRowView] = [:]

    init(theme: Theme, texts: WelcomeTexts, keymap: Keymap) {
        self.theme = theme
        self.texts = texts
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: content(keymap: keymap), theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(texts.title)
        setAccessibilityIdentifier("smalti.welcome")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    func show(_ state: WelcomeState, installing: Set<WelcomeRow>) {
        for (row, view) in rows {
            let status = installing.contains(row) ? texts.installing : state.status(of: row, texts: texts)
            view.show(
                status: status, isSelected: row == state.selected,
                isFailed: !installing.contains(row) && state.isFailed(row))
        }
    }

    /// Key codes, the same on every layout.
    private enum Key {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let space: UInt16 = 49
        static let returns: Set<UInt16> = [36, 76]
        static let escape: UInt16 = 53
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Key.up: onMove?(-1)
        case Key.down: onMove?(1)
        case Key.left: onCycleTheme?(-1)
        case Key.right: onCycleTheme?(1)
        case Key.space: onInstall?()
        case let code where Key.returns.contains(code): onFinish?()
        case Key.escape: onSkip?()
        default: super.keyDown(with: event)
        }
    }

    private func content(keymap: Keymap) -> NSView {
        let tokens = theme.welcome
        let title = label(texts.title, (tokens.titleFontSize, 600, theme.text.title))
        let subtitle = label(
            WelcomeContent.subtitle(keymap: keymap, texts: texts), (tokens.subtitleFontSize, 400, theme.text.secondary))
        let rowViews = WelcomeRow.allCases.map { row in
            let view = WelcomeRowView(title: texts.rows[row] ?? "", identifier: Self.identifier(row), theme: theme)
            view.onClick = { [weak self] in self?.onChoose?(row) }
            rows[row] = view
            return view
        }
        let body = NSStackView(views: [title, subtitle, shortcuts(keymap: keymap)] + rowViews)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = tokens.lineGap
        body.setCustomSpacing(tokens.lineGap * 2, after: body.arrangedSubviews[2])
        body.translatesAutoresizingMaskIntoConstraints = false
        let padded = NSView()
        padded.addSubview(body)
        NSLayoutConstraint.activate(
            [
                body.leadingAnchor.constraint(equalTo: padded.leadingAnchor, constant: tokens.padding),
                body.widthAnchor.constraint(equalToConstant: tokens.width - 2 * tokens.padding),
                body.topAnchor.constraint(equalTo: padded.topAnchor, constant: tokens.padding),
                body.bottomAnchor.constraint(equalTo: padded.bottomAnchor, constant: -tokens.padding),
            ] + rowViews.map { $0.widthAnchor.constraint(equalTo: body.widthAnchor) })
        let stack = NSStackView(views: [padded, OverlayBox.separator(theme: theme), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        return stack
    }

    /// Two columns of `⌘K  Paleta de comandos`, in the order of `WelcomeContent`.
    private func shortcuts(keymap: Keymap) -> NSView {
        let tokens = theme.welcome
        let cells = WelcomeContent.shortcuts(keymap: keymap, texts: texts).map { shortcut -> NSView in
            let name = label(shortcut.label, (tokens.rowFontSize, 400, theme.text.primary))
            let pair = NSStackView(views: [KbdView(shortcut.keys, theme: theme), name])
            pair.spacing = tokens.shortcutGap
            return pair
        }
        let half = (cells.count + 1) / 2
        let rows = (0..<half).map { index in
            [cells[index], cells.indices.contains(index + half) ? cells[index + half] : NSView()]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = tokens.shortcutGap
        grid.columnSpacing = tokens.lineGap * 2
        return grid
    }

    private func footer() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let hint = { (keys: String, hint: WelcomeHint) in
            OverlayBox.hint(keys, self.texts.hints[hint] ?? "", theme: self.theme)
        }
        let row = NSStackView(views: [
            hint("↑↓", .choose), hint(texts.spaceKey, .install), hint("←→", .theme), spacer, hint("esc", .skip),
            hint("↩", .start),
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }

    private func label(_ text: String, _ style: (size: Double, weight: Int, color: RGBAColor)) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = theme.interfaceFont(size: style.size, weight: style.weight)
        field.textColor = style.color.nsColor
        return field
    }

    private static func identifier(_ row: WelcomeRow) -> String {
        switch row {
        case .claude: "smalti.welcome.claude"
        case .neovim: "smalti.welcome.neovim"
        case .theme: "smalti.welcome.theme"
        }
    }
}

/// One choosable row: its title on the left and its status (or the theme) on the right; chosen, it takes ⌘K's
/// selection background and focus ring.
@MainActor
private final class WelcomeRowView: NSView {
    var onClick: (() -> Void)?
    private let theme: Theme
    private let status = NSTextField(labelWithString: "")

    init(title: String, identifier: String, theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.palette.rowCornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        let name = NSTextField(labelWithString: title)
        name.font = theme.interfaceFont(size: theme.welcome.rowFontSize)
        name.textColor = theme.text.title.nsColor
        status.font = theme.interfaceFont(size: theme.welcome.rowFontSize)
        status.alignment = .right
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [name, spacer, status])
        row.edgeInsets = NSEdgeInsets(
            top: 0, left: theme.palette.fieldPadding, bottom: 0, right: theme.palette.fieldPadding)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: theme.welcome.rowHeight),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityIdentifier(identifier)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(status text: String, isSelected: Bool, isFailed: Bool) {
        status.stringValue = text
        status.textColor = (isFailed ? theme.agent.failed : theme.text.secondary).nsColor
        layer?.backgroundColor = isSelected ? theme.palette.selection.nsColor.cgColor : NSColor.clear.cgColor
        layer?.borderColor = (isSelected ? theme.focus.ring : RGBAColor.clear).nsColor.cgColor
        setAccessibilityValue(text)
        setAccessibilitySelected(isSelected)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
