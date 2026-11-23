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
    private var tableHeight: NSLayoutConstraint?
    var onSelect: ((String) -> Void)? {
        get { table.onSelect }
        set { table.onSelect = newValue }
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
        let strip = NSStackView(views: [title, subtitle, spacer, period, KbdView("esc", theme: theme)])
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
    func showReading(period current: ObservatoryPeriod) {
        period.show(current.title)
        cards.showReading()
    }

    func show(_ report: ObservatoryReport, snapshot: ObservatorySnapshot, period current: ObservatoryPeriod) {
        let zone = TimeZone.autoupdatingCurrent
        period.show(current.title)
        cards.show(report.summary, timeZone: zone)
        let tokens = theme.observatory
        tableHeight?.constant =
            tokens.tableHeaderHeight + tokens.rowHeight * Double(min(max(report.rows.count, 1), Self.visibleRows))
        table.show(report.rows, selected: report.detail?.sessionID)
        detail.show(report.detail, timeZone: zone)
        localModels.show(LocalModelsFigures.make(snapshot.localModels, now: snapshot.now))
        system.show(SystemFigures.make(snapshot), cpuHistory: snapshot.cpuHistory, gpuHistory: snapshot.gpuHistory)
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
