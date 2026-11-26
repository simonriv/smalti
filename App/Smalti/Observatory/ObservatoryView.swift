import AppKit
import SmaltiCore

/// Observatorio.dc.html over the whole window: a 40 pt strip ("Observatorio", the period, esc), then the summary
/// cards, the sessions table and the selected session's detail on the left, Ollama and the system on the right.
@MainActor
final class ObservatoryView: NSView {
    private let theme: Theme
    private let cards: SummaryCardsView
    private let table: SessionTableView
    private let detail: DetailView
    private let localModels: LocalModelsView
    private let system: SystemView
    private let period: PeriodPill
    /// F6: "Todas · Claude Code · OpenCode · Locales".
    private let filters: FilterChips
    private var tableHeight: NSLayoutConstraint?
    var onSelect: ((String) -> Void)? {
        get { table.onSelect }
        set { table.onSelect = newValue }
    }
    var onSelectFilter: ((ObservatoryFilter) -> Void)? {
        get { filters.onSelect }
        set { filters.onSelect = newValue }
    }

    var onCyclePeriod: (() -> Void)? {
        get { period.onClick }
        set { period.onClick = newValue }
    }

    /// The keys the observatory itself owns (⌘⇧A and ⌘P go through the keymap).
    enum Key {
        case up, down, open, close
    }

    var onKey: ((Key) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        onKey?(key)
    }

    private static func key(for event: NSEvent) -> Key? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.specialKey {
        case .upArrow: return .up
        case .downArrow: return .down
        case .carriageReturn, .enter: return .open
        default: return event.keyCode == escapeKeyCode ? .close : nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    /// Rows the table shows before it scrolls; the detail card takes the rest of the height.
    private static let visibleRows = 5

    init(theme: Theme) {
        self.theme = theme
        cards = SummaryCardsView(theme: theme)
        table = SessionTableView(theme: theme)
        detail = DetailView(theme: theme)
        localModels = LocalModelsView(theme: theme)
        system = SystemView(theme: theme)
        period = PeriodPill(theme: theme)
        filters = FilterChips(theme: theme)
        super.init(frame: .zero)
        layoutStrip(layoutBody())
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.observatory")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

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
        tableHeight = tableCard.heightAnchor.constraint(equalToConstant: tokens.tableHeaderHeight + tokens.rowHeight)
        tableHeight?.isActive = true
        let left = column([cards, tableCard, detail], fill: detail)
        let right = column([localModels, system], fill: system)
        let body = NSView()
        for side in [left, right] {
            side.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(side)
        }
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: body.topAnchor, constant: tokens.padding),
            left.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -tokens.padding),
            left.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: tokens.padding),
            left.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -tokens.gap),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            right.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -tokens.padding),
            right.widthAnchor.constraint(equalToConstant: tokens.sideColumnWidth),
        ])
        return body
    }

    private func column(_ views: [NSView], fill: NSView) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = theme.observatory.gap
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        // `fill` (the last panel) takes the rest of the column; the other panels size to their content.
        fill.setContentHuggingPriority(.init(1), for: .vertical)
        fill.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
        return stack
    }

    private func layoutStrip(_ body: NSView) {
        let tokens = theme.observatory
        let title = ObservatoryText.label(
            "Observatorio",
            .init(size: tokens.stripTitleSize, color: theme.text.title, weight: tokens.stripTitleWeight), theme: theme)
        let subtitle = ObservatoryText.label(
            "agentes y modelos en esta máquina", .init(size: tokens.stripSubtitleSize, color: theme.text.secondary),
            theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let separator = NSBox()
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = theme.observatory.pillBorder.nsColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth),
            separator.heightAnchor.constraint(equalToConstant: theme.observatoryFilter.separatorHeight),
        ])
        let strip = NSStackView(views: [
            title, subtitle, spacer, filters, separator, period, KbdView("esc", theme: theme),
        ])
        strip.spacing = tokens.stripGap
        strip.edgeInsets = NSEdgeInsets(
            top: 0, left: tokens.stripPaddingLeading, bottom: 0, right: tokens.stripPaddingTrailing)
        let border = NSBox()
        border.boxType = .custom
        border.borderWidth = 0
        border.fillColor = theme.strip.bottomBorder.nsColor
        for view in [strip, border, body] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor), strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: theme.chrome.topStripHeight),
            border.topAnchor.constraint(equalTo: strip.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth),
            body.topAnchor.constraint(equalTo: border.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Before the first snapshot: the cards say they are reading, everything else stays empty.
    func show(filter: ObservatoryFilter) {
        filters.show(filter)
    }

    func showReading(period current: ObservatoryPeriod) {
        period.show(current.title(copy: .spanish /* T9 */))
        cards.showReading()
    }

    func show(_ report: ObservatoryReport, snapshot: ObservatorySnapshot, period current: ObservatoryPeriod) {
        let zone = TimeZone.autoupdatingCurrent
        period.show(current.title(copy: .spanish /* T9 */))
        cards.show(report.summary, timeZone: zone)
        let tokens = theme.observatory
        tableHeight?.constant =
            tokens.tableHeaderHeight + tokens.rowHeight * Double(min(max(report.rows.count, 1), Self.visibleRows))
        table.show(report.rows, selected: report.detail?.sessionID)
        detail.show(report.detail, timeZone: zone)
        localModels.show(LocalModelsFigures.make(snapshot.localModels, now: snapshot.now, copy: .spanish /* T9 */))
        system.show(
            SystemFigures.make(snapshot, copy: .spanish /* T9 */), cpuHistory: snapshot.cpuHistory,
            gpuHistory: snapshot.gpuHistory,
            footnote: report.footnote)
    }
}

/// The period pill ("Hoy", "7 días", "30 días"): a click or ⌘P moves to the next period.
@MainActor
private final class PeriodPill: NSView {
    private let label: NSTextField
    var onClick: (() -> Void)?

    init(theme: Theme) {
        let tokens = theme.observatory
        label = ObservatoryText.label(
            "", .init(size: tokens.pillFontSize, color: tokens.pillText, weight: tokens.pillWeight), theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = tokens.pillRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = tokens.pillBorder.nsColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: tokens.pillHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.pillPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.pillPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.observatory.period")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ title: String) {
        label.stringValue = title
        setAccessibilityLabel(title)
        setAccessibilityValue(title)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}

/// F6: the observatory's harness chips (Observatorio.dc.html): the chosen one with the accent's ring and glow.
@MainActor
private final class FilterChips: NSStackView {
    var onSelect: ((ObservatoryFilter) -> Void)?
    private let theme: Theme
    private var buttons: [ObservatoryFilter: NSButton] = [:]

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let tokens = theme.observatoryFilter
        spacing = tokens.chipGap
        for filter in ObservatoryFilter.allCases {
            let button = NSButton(title: filter.title, target: self, action: #selector(clicked(_:)))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = tokens.chipRadius
            button.layer?.borderWidth = theme.chrome.hairlineWidth
            button.tag = ObservatoryFilter.allCases.firstIndex(of: filter) ?? 0
            button.setAccessibilityIdentifier("smalti.observatory.filter.\(button.tag)")
            button.heightAnchor.constraint(equalToConstant: tokens.chipHeight).isActive = true
            buttons[filter] = button
            addArrangedSubview(button)
        }
        show(.all)
        for button in buttons.values {
            button.widthAnchor.constraint(
                equalToConstant: ceil(button.attributedTitle.size().width) + 2 * tokens.chipPadding
            ).isActive = true
        }
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ chosen: ObservatoryFilter) {
        let tokens = theme.observatory
        let chips = theme.observatoryFilter
        for (filter, button) in buttons {
            let isChosen = filter == chosen
            button.attributedTitle = NSAttributedString(
                string: filter.title,
                attributes: [
                    .font: theme.interfaceFont(size: tokens.pillFontSize, weight: tokens.pillWeight),
                    .foregroundColor: (isChosen ? chips.chosenText : chips.inactiveText).nsColor,
                ])
            button.layer?.borderColor = (isChosen ? chips.chosenBorder : .clear).nsColor.cgColor
            button.layer?.backgroundColor = (isChosen ? chips.chosenBackground : .clear).nsColor.cgColor
            button.setAccessibilityValue(isChosen ? "selected" : "")
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        let all = ObservatoryFilter.allCases
        guard all.indices.contains(sender.tag) else { return }
        onSelect?(all[sender.tag])
    }
}
