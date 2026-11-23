import AppKit
import SmaltiCore

/// The ⌃R palette (approved mockup over `Paleta.dc.html`): the ⌘K glass box centred on the pane, a search field
/// with the "Este directorio" / "Todos" chips, rows with the command (matches in the accent), the last exit as a
/// dot, how long ago and how many times, and the footer "↩ insertar · ⌘↩ ejecutar · ⇥ cambiar ámbito · esc cerrar".
@MainActor
final class HistoryPaletteView: NSView {
    static let emptyHistory = "Historial vacío: se llena con lo que ejecutes en Smalti"
    static let noMatches = "Sin coincidencias"
    /// Rows shown at once; the selection scrolls the window.
    static let visibleRows = 8

    let field = PaletteField()
    /// ⌘↩: reaches the view as a key equivalent, not as the field's newline.
    var onCommandReturn: (() -> Void)?
    private let theme: Theme
    private let list = NSStackView()
    private let directoryChip = NSTextField(labelWithString: "Este directorio")
    private let everywhereChip = NSTextField(labelWithString: "Todos")
    private let placeholder = NSTextField(labelWithString: "")

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let palette = theme.palette
        wantsLayer = true
        layer?.cornerRadius = palette.cornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = palette.border.nsColor.cgColor
        layer?.backgroundColor = palette.background.nsColor.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(palette.shadowOpacity)
        layer?.shadowRadius = palette.shadowBlur / 2
        layer?.shadowOffset = CGSize(width: 0, height: -palette.shadowOffsetY)
        let stack = NSStackView(views: [fieldRow(), separator(), listArea(), separator(), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.historyPalette")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        onCommandReturn?()
        return true
    }

    func showScope(everywhere: Bool) {
        style(directoryChip, isOn: !everywhere)
        style(everywhereChip, isOn: everywhere)
    }

    /// The rows, or the empty or no-match line.
    func show(_ hits: [HistoryHit], selected: Int, now: Date, isHistoryEmpty: Bool) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        placeholder.stringValue = isHistoryEmpty ? Self.emptyHistory : Self.noMatches
        placeholder.isHidden = !hits.isEmpty
        let first = max(0, min(selected - Self.visibleRows + 1, hits.count - Self.visibleRows))
        for index in hits.indices.dropFirst(first).prefix(Self.visibleRows) {
            list.addArrangedSubview(HistoryRowView(hits[index], isSelected: index == selected, now: now, theme: theme))
        }
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
        field.setAccessibilityLabel("Buscar en el historial")
        field.setAccessibilityIdentifier("smalti.historyField")
        directoryChip.setAccessibilityIdentifier("smalti.historyScopeDirectory")
        everywhereChip.setAccessibilityIdentifier("smalti.historyScopeAll")
        for chip in [directoryChip, everywhereChip] {
            chip.font = theme.interfaceFont(size: palette.footerFontSize, weight: 500)
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 6
            chip.layer?.borderWidth = 1
        }
        showScope(everywhere: false)
        let row = NSStackView(views: [prefix, field, directoryChip, everywhereChip])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func style(_ chip: NSTextField, isOn: Bool) {
        chip.textColor = (isOn ? theme.accent : theme.text.secondary).nsColor
        chip.layer?.borderColor =
            (isOn ? theme.accent.withAlpha(0.5) : RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.1))
            .nsColor.cgColor
        chip.setAccessibilitySelected(isOn)
    }

    private func listArea() -> NSView {
        let palette = theme.palette
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        placeholder.font = theme.interfaceFont(size: palette.rowFontSize)
        placeholder.textColor = theme.text.secondary.nsColor
        placeholder.setAccessibilityIdentifier("smalti.historyEmpty")
        let area = NSStackView(views: [list, placeholder])
        area.orientation = .vertical
        area.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        return area
    }

    private func footer() -> NSView {
        let palette = theme.palette
        let hints = [("↩", "insertar"), ("⌘↩", "ejecutar"), ("⇥", "cambiar ámbito"), ("esc", "cerrar")].map {
            key, action in
            let label = NSTextField(labelWithString: " \(action)")
            label.font = theme.interfaceFont(size: palette.footerFontSize)
            label.textColor = theme.text.secondary.nsColor
            let hint = NSStackView(views: [KbdView(key, theme: theme), label])
            hint.spacing = 0
            return hint as NSView
        }
        let row = NSStackView(views: hints)
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
}

/// One ⌃R row: the command with its matched characters in the accent, then the last exit's dot, the time since
/// its last use and `×N`.
@MainActor
final class HistoryRowView: NSView {
    init(_ hit: HistoryHit, isSelected: Bool, now: Date, theme: Theme) {
        super.init(frame: .zero)
        let palette = theme.palette
        wantsLayer = true
        layer?.cornerRadius = palette.rowCornerRadius
        layer?.backgroundColor = isSelected ? palette.selection.nsColor.cgColor : nil
        let command = NSTextField(labelWithAttributedString: Self.highlighted(hit, theme: theme))
        command.lineBreakMode = .byTruncatingTail
        let dot = NSTextField(labelWithString: "●")
        dot.font = theme.interfaceFont(size: 9)
        dot.textColor = Self.color(for: hit.stats.lastExit, theme: theme).nsColor
        let meta = NSTextField(
            labelWithString:
                "\(HistorySearch.ago(hit.stats.lastUsed, now: now, calendar: .current))   ×\(hit.stats.uses)")
        meta.font = theme.interfaceFont(size: palette.footerFontSize)
        meta.textColor = theme.text.secondary.nsColor
        let row = NSStackView(views: [command, NSView(), dot, meta])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 32),
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
        let font = theme.monospacedFont(size: 12)
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

    /// Green for 0, red for a failure, the hollow grey of "detenido" when the exit is unknown.
    private static func color(for exit: Int?, theme: Theme) -> RGBAColor {
        guard let exit else { return theme.agent.stopped }
        return exit == 0 ? theme.agent.working : theme.agent.failed
    }
}
