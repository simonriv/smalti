import AppKit
import SmaltiCore

/// "Todas las sesiones de agentes" (Reanudar.dc.html, right column): header, search field, harness chips, the
/// sessions and the footer. The same view is the restore screen's column and, inside the ⌘K glass, the ⌘⇧O card.
/// It draws `SessionSearchState`; the controller decides.
@MainActor
final class SessionSearchView: NSView {
    let field = NSTextField()
    var onChip: ((Int) -> Void)?
    var onClickRow: ((String) -> Void)?
    /// ⌘↩: fork the selected session. An unbound ⌘↩ never reaches the field as `insertNewline:`.
    var onCommandReturn: (() -> Void)?

    private let theme: Theme
    private let chips = NSStackView()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let notes = NSStackView()
    private lazy var source = SessionListSource(theme: theme)

    /// `column`: the restore screen's column background and left border; the card gets the ⌘K glass instead.
    init(theme: Theme, column: Bool) {
        self.theme = theme
        super.init(frame: .zero)
        let tokens = theme.sessionSearch
        let stack = NSStackView(views: [header(), fieldBox(), chips, notes, scroll, footer()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.gap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.paddingVertical, left: tokens.paddingHorizontal, bottom: tokens.paddingVertical,
            right: tokens.paddingHorizontal)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        chips.spacing = tokens.chipGap
        notes.orientation = .vertical
        notes.alignment = .leading
        configureList(tokens)
        if column {
            wantsLayer = true
            layer?.backgroundColor = tokens.background.nsColor.cgColor
            embed(stack)
            addLeftBorder(tokens)
        } else {
            OverlayBox.decorate(self, around: stack, theme: theme)
        }
        for view in [field, chips, notes, scroll] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * tokens.paddingHorizontal).isActive =
                true
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Todas las sesiones de agentes")
        setAccessibilityIdentifier("sessions.search")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        if layer?.shadowOpacity ?? 0 > 0 { OverlayBox.updateShadow(of: self, theme: theme) }
    }

    /// ⌘1…⌘5 choose a chip wherever the focus is inside the search; ⌘↩ forks.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if HistoryPaletteView.isCommandReturn(event), let onCommandReturn {
            onCommandReturn()
            return true
        }
        guard let chip = Self.chipIndex(forCommandDigit: event) else { return super.performKeyEquivalent(with: event) }
        onChip?(chip)
        return true
    }

    /// ⌘1…⌘5 → the chip's index; nil for any other key.
    static func chipIndex(forCommandDigit event: NSEvent) -> Int? {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
            let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
            (1...SessionSearchState.chips(.spanish /* T9 */).count) ~= digit
        else { return nil }
        return digit - 1
    }

    func render(_ state: SessionSearchState, rows: [SessionSearchRow], notice: String? = nil) {
        chips.setViews(
            SessionSearchState.chips(.spanish /* T9 */).enumerated().map { index, chip in
                chipView(chip.title, index: index, isSelected: index == state.chipIndex)
            }, in: .leading)
        notes.setViews(
            ([notice].compactMap { $0 } + state.failureMessages(.spanish /* T9 */)
                + [state.emptyText(.spanish /* T9 */)].compactMap { $0 }).map { note($0) },
            in: .leading)
        source.rows = rows
        source.selectedID = state.selected?.id
        table.reloadData()
        if let index = rows.firstIndex(where: { $0.id == state.selected?.id }) { table.scrollRowToVisible(index) }
    }

    // MARK: - Parts

    private func header() -> NSView {
        let tokens = theme.sessionSearch
        let title = NSTextField(labelWithString: "")
        title.attributedStringValue = NSAttributedString(
            string: "TODAS LAS SESIONES DE AGENTES",
            attributes: [
                .font: theme.interfaceFont(size: theme.resume.tagFontSize),
                .kern: theme.resume.tagFontSize * tokens.headerLetterSpacing,
                .foregroundColor: tokens.secondaryText.nsColor,
            ])
        title.setAccessibilityLabel("Todas las sesiones de agentes")
        let subtitle = label(
            "Leídas del disco de cada harness, aunque no las abrieras aquí.", size: tokens.subtitleFontSize,
            color: tokens.secondaryText)
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.headerGap
        return stack
    }

    private func fieldBox() -> NSView {
        let tokens = theme.sessionSearch
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: tokens.fieldFontSize)
        field.textColor = tokens.selectedText.nsColor
        field.placeholderAttributedString = NSAttributedString(
            string: "Buscar por tema, proyecto o archivo",
            attributes: [
                .font: theme.interfaceFont(size: tokens.fieldFontSize), .foregroundColor: tokens.secondaryText.nsColor,
            ])
        field.setAccessibilityLabel("Buscar sesiones")
        field.setAccessibilityIdentifier("sessions.field")
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = tokens.secondaryText.nsColor
        icon.symbolConfiguration = .init(pointSize: tokens.fieldGlyphSize, weight: .regular)
        let row = NSStackView(views: [icon, field])
        row.spacing = tokens.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: tokens.fieldPadding, bottom: 0, right: tokens.fieldPadding)
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = tokens.fieldCornerRadius
        box.layer?.borderWidth = theme.chrome.hairlineWidth
        box.layer?.borderColor = tokens.fieldBorder.nsColor.cgColor
        box.layer?.backgroundColor = tokens.fieldBackground.nsColor.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(row)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: tokens.fieldHeight),
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func chipView(_ title: String, index: Int, isSelected: Bool) -> NSView {
        let tokens = theme.sessionSearch
        let chip = ChipButton(title: title) { [weak self] in self?.onChip?(index) }
        chip.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: theme.interfaceFont(size: tokens.chipFontSize, weight: tokens.chipWeight),
                .foregroundColor: (isSelected ? tokens.selectedText : tokens.chipText).nsColor,
            ])
        chip.layer?.backgroundColor =
            (isSelected ? theme.accent.withAlpha(tokens.chipSelectedAlpha) : tokens.chipBackground).nsColor.cgColor
        chip.insets = NSEdgeInsets(
            top: tokens.chipPaddingVertical, left: tokens.chipPaddingHorizontal, bottom: tokens.chipPaddingVertical,
            right: tokens.chipPaddingHorizontal)
        chip.setAccessibilityIdentifier("sessions.chip.\(index)")
        chip.setAccessibilityValue(isSelected ? "selected" : "")
        return chip
    }

    /// Virtualized like ⌘K's list (spec F6): only the rows on screen have views.
    private func configureList(_ tokens: SessionSearchTokens) {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session")))
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: tokens.rowGap)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAutomaticRowHeights = true
        table.focusRingType = .none
        table.refusesFirstResponder = true
        source.onClick = { [weak self] id in self?.onClickRow?(id) }
        table.dataSource = source
        table.delegate = source
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setAccessibilityIdentifier("sessions.list")
    }

    private func footer() -> NSView {
        let text = NSTextField(
            wrappingLabelWithString:
                "Enter abre la sesión en un panel nuevo con el comando correcto del harness. ⌘Enter la bifurca cuando el harness lo permite."
        )
        text.font = theme.interfaceFont(size: theme.sessionSearch.footerFontSize)
        text.textColor = theme.sessionSearch.secondaryText.nsColor
        return text
    }

    private func note(_ text: String) -> NSView {
        let view = label(text, size: theme.sessionSearch.rowDetailFontSize, color: theme.sessionSearch.secondaryText)
        view.setAccessibilityIdentifier("sessions.note")
        return view
    }

    private func label(_ text: String, size: Double, color: RGBAColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = theme.interfaceFont(size: size)
        field.textColor = color.nsColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func embed(_ stack: NSView) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func addLeftBorder(_ tokens: SessionSearchTokens) {
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = tokens.border.nsColor.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor), border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth),
        ])
    }
}

/// One session: title and day on the first line, "Harness · proyecto · detalle" below.
@MainActor
final class SessionRowView: NSView {
    var onClick: (() -> Void)?

    init(_ row: SessionSearchRow, theme: Theme, isSelected: Bool) {
        super.init(frame: .zero)
        let tokens = theme.sessionSearch
        let title = NSTextField(labelWithString: row.title)
        title.font = theme.interfaceFont(size: tokens.rowTitleFontSize)
        title.textColor = (isSelected ? tokens.selectedText : theme.text.primary).nsColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let day = NSTextField(labelWithString: row.day)
        day.font = theme.interfaceFont(size: tokens.rowTitleFontSize)
        day.textColor = tokens.secondaryText.nsColor
        let top = NSStackView(views: [title, NSView(), day])
        let detail = NSTextField(labelWithString: row.detail)
        detail.font = theme.interfaceFont(size: tokens.rowDetailFontSize)
        detail.textColor = tokens.secondaryText.nsColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [top, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.rowLineGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.rowPaddingVertical, left: tokens.rowPaddingHorizontal, bottom: tokens.rowPaddingVertical,
            right: tokens.rowPaddingHorizontal)
        top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * tokens.rowPaddingHorizontal).isActive =
            true
        wantsLayer = true
        layer?.cornerRadius = tokens.rowCornerRadius
        layer?.backgroundColor =
            (isSelected ? tokens.rowSelected : .clear).nsColor.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(row.title)
        setAccessibilityValue(row.detail)
        setAccessibilityIdentifier("sessions.row.\(row.id)")
        setAccessibilitySelected(isSelected)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A rounded, filled chip that runs `action` on click.
@MainActor
final class ChipButton: NSButton {
    var insets = NSEdgeInsets()
    private let run: () -> Void

    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = true
        target = self
        self.action = #selector(clicked)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    @objc private func clicked() { run() }
}

/// The session list's rows for the table: a fresh row view for each visible row, the selected one highlighted.
@MainActor
private final class SessionListSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [SessionSearchRow] = []
    var selectedID: String?
    var onClick: ((String) -> Void)?
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let item = rows[row]
        let view = SessionRowView(item, theme: theme, isSelected: item.id == selectedID)
        view.onClick = { [weak self] in self?.onClick?(item.id) }
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
