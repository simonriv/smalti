import AppKit
import SmaltiCore

/// The ⌃R palette (approved mockup over `Paleta.dc.html`): the ⌘K glass box centred on the pane, a search field
/// with the "Este directorio" / "Todos" chips, rows with the command (matches in the accent), the last exit as a
/// dot, how long ago and how many times, and the footer "↩ insertar · ⌘↩ ejecutar · ⇥ cambiar ámbito · esc cerrar".
@MainActor
final class HistoryPaletteView: NSView {
    static let emptyHistory = String(localized: "Empty history: it fills with what you run in Smalti")
    static let noMatches = String(localized: "No matches")

    let field = PaletteField()
    /// ⌘↩: reaches the view as a key equivalent, not as the field's newline.
    var onCommandReturn: (() -> Void)?
    private let theme: Theme
    private let list = NSStackView()
    private let directoryChip: Chip
    private let everywhereChip: Chip
    private let placeholder = NSTextField(labelWithString: "")

    init(theme: Theme) {
        self.theme = theme
        directoryChip = Chip(String(localized: "This folder"), identifier: "smalti.historyScopeDirectory", theme: theme)
        everywhereChip = Chip(String(localized: "All"), identifier: "smalti.historyScopeAll", theme: theme)
        super.init(frame: .zero)
        layoutBox(content: makeContent())
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.historyPalette")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard HistoryPaletteView.isCommandReturn(event) else { return super.performKeyEquivalent(with: event) }
        onCommandReturn?()
        return true
    }

    /// ⌘↩ from the main keyboard or the keypad (whose Enter also carries `.numericPad`).
    static func isCommandReturn(_ event: NSEvent) -> Bool {
        (event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter)
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
    }

    func showScope(everywhere: Bool) {
        directoryChip.isOn = !everywhere
        everywhereChip.isOn = everywhere
    }

    /// The rows around `selected`, or the empty-history or no-match line.
    func show(_ hits: [HistoryHit], selected: Int, now: Date, isHistoryEmpty: Bool) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        placeholder.stringValue = isHistoryEmpty ? Self.emptyHistory : Self.noMatches
        placeholder.isHidden = !hits.isEmpty
        let rows = theme.historyPalette.visibleRows
        let first = max(0, min(selected - rows + 1, hits.count - rows))
        for index in hits.indices.dropFirst(first).prefix(rows) {
            list.addArrangedSubview(HistoryRowView(hits[index], isSelected: index == selected, now: now, theme: theme))
        }
    }

    /// Shadow outside, blur and tint inside the rounded box, border on top, as ⌘K.
    private func layoutBox(content: NSView) {
        let palette = theme.palette
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(palette.shadowOpacity)
        layer?.shadowRadius = palette.shadowBlur / 2
        layer?.shadowOffset = CGSize(width: 0, height: -palette.shadowOffsetY)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = palette.cornerRadius
        blur.layer?.masksToBounds = true
        for view in [blur, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            pin(view, to: self)
        }
    }

    private func makeContent() -> NSView {
        let palette = theme.palette
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = palette.cornerRadius
        content.layer?.borderWidth = theme.chrome.hairlineWidth
        content.layer?.borderColor = palette.border.nsColor.cgColor
        content.layer?.backgroundColor = palette.background.nsColor.cgColor
        let stack = NSStackView(views: [fieldRow(), separator(), listArea(), separator(), footer()])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        pin(stack, to: content)
        return content
    }

    private func fieldRow() -> NSView {
        let palette = theme.palette
        let prefix = NSTextField(labelWithString: "⌃R")
        prefix.font = theme.interfaceFont(size: palette.fieldFontSize)
        prefix.textColor = theme.text.secondary.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.fieldFontSize)
        field.textColor = theme.text.title.nsColor
        field.setAccessibilityLabel(String(localized: "Search history"))
        field.setAccessibilityIdentifier("smalti.historyField")
        showScope(everywhere: false)
        let row = NSStackView(views: [prefix, field, directoryChip, everywhereChip])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func listArea() -> NSView {
        let inset = theme.historyPalette.listInset
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        placeholder.font = theme.interfaceFont(size: theme.palette.rowFontSize)
        placeholder.textColor = theme.text.secondary.nsColor
        placeholder.setAccessibilityIdentifier("smalti.historyEmpty")
        let area = NSStackView(views: [list, placeholder])
        area.orientation = .vertical
        area.alignment = .width
        area.edgeInsets = NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        return area
    }

    private func footer() -> NSView {
        let palette = theme.palette
        let hints: [NSView] = [
            ("↩", String(localized: "insert")), ("⌘↩", String(localized: "run")),
            ("⇥", String(localized: "switch scope")), ("esc", String(localized: "close")),
        ].map {
            key, action in
            let label = NSTextField(labelWithString: " \(action)")
            label.font = theme.interfaceFont(size: palette.footerFontSize)
            label.textColor = theme.text.secondary.nsColor
            let hint = NSStackView(views: [KbdView(key, theme: theme), label])
            hint.spacing = 0
            return hint
        }
        // Left-aligned, as the mockup: the spacer takes the remaining width.
        let row = NSStackView(views: hints + [NSView()])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.palette.footerBorder.nsColor.cgColor
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    private func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// A scope chip: its label inside a rounded border, the accent when on. `isSelected` tells the tests which one is.
@MainActor
private final class Chip: NSView {
    private let label: NSTextField
    private let theme: Theme

    init(_ title: String, identifier: String, theme: Theme) {
        self.theme = theme
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        let tokens = theme.historyPalette
        wantsLayer = true
        layer?.cornerRadius = tokens.chipCornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        label.font = theme.interfaceFont(size: theme.palette.footerFontSize, weight: 500)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.chipPaddingHorizontal),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.chipPaddingHorizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: tokens.chipPaddingVertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -tokens.chipPaddingVertical),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityIdentifier(identifier)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    var isOn = false {
        didSet {
            let tokens = theme.historyPalette
            label.textColor = (isOn ? theme.accent : theme.text.secondary).nsColor
            layer?.borderColor =
                (isOn ? theme.accent.withAlpha(tokens.chipActiveBorderAlpha) : tokens.chipBorder).nsColor.cgColor
            setAccessibilitySelected(isOn)
        }
    }
}

/// One ⌃R row: the command with its matched characters in the accent, then the last exit's dot, the time since
/// its last use and `×N`.
@MainActor
final class HistoryRowView: NSView {
    init(_ hit: HistoryHit, isSelected: Bool, now: Date, theme: Theme) {
        super.init(frame: .zero)
        let palette = theme.palette
        let tokens = theme.historyPalette
        wantsLayer = true
        layer?.cornerRadius = palette.rowCornerRadius
        layer?.backgroundColor = isSelected ? palette.selection.nsColor.cgColor : nil
        let command = NSTextField(labelWithAttributedString: Self.highlighted(hit, theme: theme))
        command.lineBreakMode = .byTruncatingTail
        let dot = NSTextField(labelWithString: "●")
        dot.font = theme.interfaceFont(size: tokens.dotSize)
        dot.textColor = Self.color(for: hit.stats.lastExit, theme: theme).nsColor
        let ago = HistorySearch.ago(hit.stats.lastUsed, now: now, calendar: .current, texts: .current)
        let meta = NSTextField(labelWithString: "\(ago)   ×\(hit.stats.uses)")
        meta.font = theme.interfaceFont(size: palette.footerFontSize)
        meta.textColor = theme.text.secondary.nsColor
        let row = NSStackView(views: [command, NSView(), dot, meta])
        row.spacing = tokens.rowGap
        row.edgeInsets = NSEdgeInsets(
            top: 0, left: tokens.rowPaddingHorizontal, bottom: 0, right: tokens.rowPaddingHorizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: tokens.rowHeight),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityIdentifier("smalti.historyRow")
        setAccessibilityLabel(hit.stats.command)
        setAccessibilitySelected(isSelected)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private static func highlighted(_ hit: HistoryHit, theme: Theme) -> NSAttributedString {
        let font = theme.monospacedFont(size: theme.historyPalette.commandFontSize)
        let text = NSMutableAttributedString(
            string: hit.stats.command, attributes: [.font: font, .foregroundColor: theme.text.primary.nsColor])
        let characters = Array(hit.stats.command)
        for range in hit.matched where range.upperBound <= characters.count {
            let start = String(characters[..<range.lowerBound]).utf16.count
            let length = String(characters[range]).utf16.count
            text.addAttribute(
                .foregroundColor, value: theme.accent.nsColor, range: NSRange(location: start, length: length))
        }
        return text
    }

    /// Green for 0, red for a failure, the grey of "detenido" when the exit is unknown.
    private static func color(for exit: Int?, theme: Theme) -> RGBAColor {
        guard let exit else { return theme.agent.stopped }
        return exit == 0 ? theme.agent.working : theme.agent.failed
    }
}
