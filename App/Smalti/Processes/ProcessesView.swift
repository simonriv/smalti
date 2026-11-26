import AppKit
import SmaltiCore

/// F8's processes and ports views over the whole window (`docs/specs/F8-assets/mockup.html`): the observatory's
/// 40 pt strip with the two views' chips, the filter, the order and the tree; the table and, on the right, the
/// chosen row's detail and a summary card; a 30 pt key footer; the amber card that confirms forcing a quit.
@MainActor
final class ProcessesView: NSView {
    /// The keys the view owns; its chords (⌘⌫, ⌘T, ⌘⇧S…) go through the keymap.
    enum Key: Equatable {
        case up, down, open, close
        case text(String)
        case deleteBackward
    }

    private let theme: Theme
    private let strip: ProcessesStrip
    private let table: ProcessesTableView
    private let detail: ProcessesDetailView
    private let totals: ProcessesTotalsView
    private let summary: PortsSummaryView
    private let footer: ProcessesFooter
    private let confirmation: ForceConfirmation
    var onKey: ((Key) -> Void)?
    var onSelect: ((String) -> Void)? {
        get { table.onSelect }
        set { table.onSelect = newValue }
    }
    var onChooseMode: ((ProcessesController.Mode) -> Void)? {
        get { strip.onChooseMode }
        set { strip.onChooseMode = newValue }
    }

    override var acceptsFirstResponder: Bool { true }

    init(theme: Theme) {
        self.theme = theme
        strip = ProcessesStrip(theme: theme)
        table = ProcessesTableView(theme: theme)
        detail = ProcessesDetailView(theme: theme)
        totals = ProcessesTotalsView(theme: theme)
        summary = PortsSummaryView(theme: theme)
        footer = ProcessesFooter(theme: theme)
        confirmation = ForceConfirmation(theme: theme)
        super.init(frame: .zero)
        layoutAll()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.processes")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        onKey?(key)
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51

    private static func key(for event: NSEvent) -> Key? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.specialKey {
        case .upArrow: return .up
        case .downArrow: return .down
        case .carriageReturn, .enter: return .open
        default: break
        }
        if event.keyCode == escapeKeyCode { return .close }
        if event.keyCode == deleteKeyCode { return .deleteBackward }
        guard let characters = event.characters, !characters.isEmpty,
            characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return .text(characters)
    }

    func show(_ screen: ProcessesScreen, filter: String) {
        strip.show(mode: screen.mode, filter: filter, order: screen.order, isTree: screen.isTree)
        table.show(screen)
        detail.show(screen.detail)
        switch screen.side {
        case .totals(let model):
            totals.isHidden = false
            summary.isHidden = true
            totals.show(model)
        case .summary(let model):
            totals.isHidden = true
            summary.isHidden = false
            summary.show(model)
        }
        footer.show(mode: screen.mode)
    }

    func showNotice(_ text: String?, isFailure: Bool) {
        footer.showNotice(text, isFailure: isFailure)
    }

    /// The confirmation to force a quit, over everything else; nil hides it.
    func showConfirmation(_ content: ForceConfirmation.Content?) {
        confirmation.show(content)
    }

    private func layoutAll() {
        let border = Self.hairline(theme.strip.bottomBorder)
        let body = layoutBody()
        let footerBorder = Self.hairline(theme.strip.bottomBorder)
        for view in [strip, border, body, footerBorder, footer, confirmation] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let hairline = theme.chrome.hairlineWidth
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor), strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: theme.chrome.topStripHeight),
            border.topAnchor.constraint(equalTo: strip.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: hairline),
            body.topAnchor.constraint(equalTo: border.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerBorder.topAnchor.constraint(equalTo: body.bottomAnchor),
            footerBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerBorder.heightAnchor.constraint(equalToConstant: hairline),
            footer.topAnchor.constraint(equalTo: footerBorder.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: theme.processes.footerHeight),
            confirmation.topAnchor.constraint(equalTo: topAnchor),
            confirmation.bottomAnchor.constraint(equalTo: bottomAnchor),
            confirmation.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmation.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func layoutBody() -> NSView {
        let tokens = theme.observatory
        let tableCard = ObservatoryCard(theme: theme, spacing: 0, height: .bare)
        table.translatesAutoresizingMaskIntoConstraints = false
        tableCard.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: tableCard.topAnchor),
            table.bottomAnchor.constraint(equalTo: tableCard.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: tableCard.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: tableCard.trailingAnchor),
        ])
        let side = NSStackView(views: [detail, totals, summary])
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = tokens.gap
        side.setHuggingPriority(.init(1), for: .vertical)
        for view in [detail, totals, summary] { view.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true }
        for card in [totals, summary] as [NSView] {
            card.setContentHuggingPriority(.init(1), for: .vertical)
            card.bottomAnchor.constraint(equalTo: side.bottomAnchor).isActive = true
        }
        let body = NSView()
        for view in [tableCard, side] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tableCard.topAnchor.constraint(equalTo: body.topAnchor, constant: tokens.padding),
            tableCard.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -tokens.padding),
            tableCard.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: tokens.padding),
            tableCard.trailingAnchor.constraint(equalTo: side.leadingAnchor, constant: -tokens.gap),
            side.topAnchor.constraint(equalTo: tableCard.topAnchor),
            side.bottomAnchor.constraint(equalTo: tableCard.bottomAnchor),
            side.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -tokens.padding),
            side.widthAnchor.constraint(equalToConstant: tokens.sideColumnWidth),
        ])
        return body
    }

    static func hairline(_ color: RGBAColor) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.fillColor = color.nsColor
        return box
    }
}

/// The strip: "Procesos · lo que corre y escucha…", the two views' chips with their chords, the filter, the order
/// and the tree, and esc.
@MainActor
private final class ProcessesStrip: NSView {
    private let theme: Theme
    private let processesChip: ModeChip
    private let portsChip: ModeChip
    private let filter: FilterField
    private let order: StripPill
    private let tree: StripPill
    var onChooseMode: ((ProcessesController.Mode) -> Void)?

    init(theme: Theme) {
        self.theme = theme
        processesChip = ModeChip(
            String(localized: "Processes"), keys: ProcessesKeys.chord(.processesToggle), theme: theme,
            identifier: "smalti.processes.mode.processes")
        portsChip = ModeChip(
            String(localized: "Ports"), keys: ProcessesKeys.chord(.portsToggle), theme: theme,
            identifier: "smalti.processes.mode.ports")
        filter = FilterField(theme: theme)
        order = StripPill(theme: theme, identifier: "smalti.processes.order")
        tree = StripPill(theme: theme, identifier: "smalti.processes.tree")
        super.init(frame: .zero)
        processesChip.onClick = { [weak self] in self?.onChooseMode?(.processes) }
        portsChip.onClick = { [weak self] in self?.onChooseMode?(.ports) }
        layoutStrip()
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func layoutStrip() {
        let tokens = theme.observatory
        let title = ObservatoryText.label(
            String(localized: "Processes"),
            .init(size: tokens.stripTitleSize, color: theme.text.title, weight: tokens.stripTitleWeight), theme: theme)
        let subtitle = ObservatoryText.label(
            String(localized: "what runs and listens on this Mac"),
            .init(size: tokens.stripSubtitleSize, color: theme.text.secondary), theme: theme)
        subtitle.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let separator = ProcessesView.hairline(tokens.pillBorder)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth),
            separator.heightAnchor.constraint(equalToConstant: theme.observatoryFilter.separatorHeight),
        ])
        let stack = NSStackView(views: [
            title, subtitle, spacer, processesChip, portsChip, separator, filter, order, tree,
            KbdView("esc", theme: theme),
        ])
        stack.spacing = tokens.stripGap
        stack.edgeInsets = NSEdgeInsets(
            top: 0, left: tokens.stripPaddingLeading, bottom: 0, right: tokens.stripPaddingTrailing)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func show(mode: ProcessesController.Mode, filter text: String, order title: String, isTree: Bool) {
        processesChip.show(isChosen: mode == .processes)
        portsChip.show(isChosen: mode == .ports)
        filter.show(text)
        order.show(title, isOn: false)
        tree.isHidden = mode == .ports
        tree.show(String(localized: "Tree"), isOn: isTree)
    }
}

/// A view's chip: its name and its chord; the shown one with the accent's ring and glow (the observatory's chips).
@MainActor
private final class ModeChip: NSView {
    private let theme: Theme
    private let title: NSTextField
    var onClick: (() -> Void)?

    init(_ text: String, keys: String, theme: Theme, identifier: String) {
        self.theme = theme
        let chips = theme.observatoryFilter
        title = ObservatoryText.label(
            text,
            .init(
                size: theme.observatory.pillFontSize, color: chips.inactiveText, weight: theme.observatory.pillWeight),
            theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = chips.chipRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        let stack = NSStackView(views: [title, KbdView(keys, theme: theme)])
        stack.spacing = theme.processes.footerKeyGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: chips.chipHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: chips.chipPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -chips.chipPadding),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)
        setAccessibilityIdentifier(identifier)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(isChosen: Bool) {
        let chips = theme.observatoryFilter
        title.textColor = (isChosen ? chips.chosenText : chips.inactiveText).nsColor
        layer?.borderColor = (isChosen ? chips.chosenBorder : .clear).nsColor.cgColor
        layer?.backgroundColor = (isChosen ? chips.chosenBackground : .clear).nsColor.cgColor
        setAccessibilityValue(isChosen ? "selected" : "")
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}

/// The order and tree pills: the observatory's period pill, with the accent's ring when the tree is on.
@MainActor
private final class StripPill: NSView {
    private let theme: Theme
    private let label: NSTextField

    init(theme: Theme, identifier: String) {
        self.theme = theme
        let tokens = theme.observatory
        label = ObservatoryText.label(
            "", .init(size: tokens.pillFontSize, color: tokens.pillText, weight: tokens.pillWeight), theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = tokens.pillRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: tokens.pillHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.pillPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.pillPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier(identifier)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ text: String, isOn: Bool) {
        label.stringValue = text
        label.textColor = (isOn ? theme.text.title : theme.observatory.pillText).nsColor
        layer?.borderColor = (isOn ? theme.focus.ring : theme.observatory.pillBorder).nsColor.cgColor
        setAccessibilityLabel(text)
        setAccessibilityValue(isOn ? "on" : "off")
    }
}

/// The filter: a magnifier and what was typed (or "filtrar" as a placeholder). Typing goes to the view's keys, not to
/// a text field, so ↑↓, ↵ and esc always stay with the view.
@MainActor
private final class FilterField: NSView {
    private let theme: Theme
    private let text: NSTextField

    init(theme: Theme) {
        self.theme = theme
        let tokens = theme.processes
        text = ObservatoryText.label("", .init(size: tokens.filterFontSize, color: theme.text.title), theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = tokens.filterRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = tokens.filterBorder.nsColor.cgColor
        layer?.backgroundColor = tokens.filterBackground.nsColor.cgColor
        let glass = MagnifierGlyph(color: theme.text.secondary)
        let stack = NSStackView(views: [glass, text])
        stack.spacing = theme.processes.footerKeyGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: tokens.filterWidth),
            heightAnchor.constraint(equalToConstant: tokens.filterHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.filterPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -tokens.filterPadding),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityIdentifier("smalti.processes.filter")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ value: String) {
        let isEmpty = value.isEmpty
        text.stringValue = isEmpty ? String(localized: "filter") : value
        text.textColor = (isEmpty ? theme.processes.placeholder : theme.text.title).nsColor
        setAccessibilityValue(value)
    }
}

/// The 12 pt magnifier of the mockup's filter: a circle and its handle.
@MainActor
private final class MagnifierGlyph: NSView {
    private let color: RGBAColor
    private static let size = 12.0

    init(color: RGBAColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size), heightAnchor.constraint(equalToConstant: Self.size),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.nsColor.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 1.4, y: 1.4, width: 7.2, height: 7.2))
        circle.lineWidth = 1.3
        circle.stroke()
        let handle = NSBezierPath()
        handle.lineWidth = 1.3
        handle.move(to: NSPoint(x: 7.7, y: 7.7))
        handle.line(to: NSPoint(x: 11, y: 11))
        handle.stroke()
    }
}

/// The 30 pt footer: the keys of the shown view and, at its right, a notice for 4 s.
@MainActor
private final class ProcessesFooter: NSView {
    private let theme: Theme
    private let keys = NSStackView()
    private let notice: NSTextField

    init(theme: Theme) {
        self.theme = theme
        let tokens = theme.processes
        notice = ObservatoryText.label("", .init(size: tokens.footerFontSize, color: tokens.notice), theme: theme)
        super.init(frame: .zero)
        keys.spacing = tokens.footerGap
        notice.setAccessibilityIdentifier("smalti.processes.notice")
        notice.alignment = .right
        notice.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [keys, notice])
        stack.spacing = tokens.footerGap
        stack.edgeInsets = NSEdgeInsets(top: 0, left: tokens.footerPadding, bottom: 0, right: tokens.footerPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private var shownMode: ProcessesController.Mode?

    func show(mode: ProcessesController.Mode) {
        guard mode != shownMode else { return }
        shownMode = mode
        keys.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for hint in ProcessesKeys.footer(for: mode) {
            let label = ObservatoryText.label(
                hint.title, .init(size: theme.processes.footerFontSize, color: theme.text.secondary), theme: theme)
            let pair = NSStackView(views: [KbdView(hint.keys, theme: theme), label])
            pair.spacing = theme.processes.footerKeyGap
            keys.addArrangedSubview(pair)
        }
    }

    func showNotice(_ text: String?, isFailure: Bool) {
        notice.stringValue = text ?? ""
        notice.setAccessibilityValue(text ?? "")
        notice.textColor = (isFailure ? theme.processes.failure : theme.processes.notice).nsColor
    }
}

/// The chords as the keymap in effect shows them, and the footer's hints for each view.
@MainActor
enum ProcessesKeys {
    static var keymap: Keymap = .standard

    static func chord(_ command: CommandID) -> String {
        keymap.chord(for: command)?.display ?? ""
    }

    struct Hint {
        let keys: String
        let title: String
    }

    static func footer(for mode: ProcessesController.Mode) -> [Hint] {
        let choose = Hint(keys: "↑↓", title: String(localized: "choose"))
        let goToPane = Hint(keys: "↵", title: String(localized: "go to pane"))
        let stop = Hint(keys: chord(.processesStop), title: String(localized: "stop"))
        let sort = Hint(keys: chord(.processesSort), title: String(localized: "sort"))
        let close = Hint(keys: "esc", title: String(localized: "close"))
        switch mode {
        case .processes:
            return [
                choose, goToPane, stop,
                Hint(keys: chord(.processesLowerPriority), title: String(localized: "lower priority")),
                Hint(keys: chord(.processesTree), title: String(localized: "tree")), sort, close,
            ]
        case .ports:
            return [
                choose, goToPane, stop, sort,
                Hint(keys: chord(.processesToggle), title: String(localized: "processes")), close,
            ]
        }
    }
}
