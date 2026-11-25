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

    private let theme: Theme
    private let chips = NSStackView()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let notes = NSStackView()
    private var rowViews: [String: SessionRowView] = [:]

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

    /// ⌘1…⌘5 choose a chip wherever the focus is inside the search.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
            (1...SessionSearchState.chips.count) ~= digit
        else { return super.performKeyEquivalent(with: event) }
        onChip?(digit - 1)
        return true
    }

    func render(_ state: SessionSearchState, rows: [SessionSearchRow]) {
        chips.setViews(
            SessionSearchState.chips.enumerated().map { index, chip in
                chipView(chip.title, index: index, isSelected: index == state.chipIndex)
            }, in: .leading)
        notes.setViews(
            (state.failureMessages + [state.emptyText].compactMap { $0 }).map { note($0) }, in: .leading)
        rowViews = [:]
        list.setViews(
            rows.map { row in
                let view = SessionRowView(row, theme: theme, isSelected: row.id == state.selected?.id)
                view.onClick = { [weak self] in self?.onClickRow?(row.id) }
                rowViews[row.id] = view
                return view
            }, in: .top)
        if let id = state.selected?.id, let view = rowViews[id] {
            list.layoutSubtreeIfNeeded()
            view.scrollToVisible(view.bounds)
        }
    }

    // MARK: - Parts

    private func header() -> NSView {
        let tokens = theme.sessionSearch
        let title = NSTextField(labelWithString: "")
        title.attributedStringValue = NSAttributedString(
            string: "TODAS LAS SESIONES DE AGENTES",
            attributes: [
                .font: theme.interfaceFont(size: theme.resume.tagFontSize), .kern: theme.resume.tagFontSize * 0.06,
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
        icon.symbolConfiguration = .init(pointSize: tokens.fieldIconSize - 2, weight: .regular)
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

    private func configureList(_ tokens: SessionSearchTokens) {
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = tokens.rowGap
        let document = FlippedView()
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
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
            (isSelected ? tokens.rowSelected : RGBAColor(red: 0, green: 0, blue: 0, alpha: 0))
            .nsColor.cgColor
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
        layer?.cornerRadius = 99
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

/// Lists grow down from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
