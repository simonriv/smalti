import AppKit
import SmaltiCore

/// The chosen row's card: "Proceso · node", the full command in a mono block, the facts and the actions with their
/// keys (or why none applies).
@MainActor
final class ProcessesDetailView: NSView {
    private let theme: Theme
    private let card: ObservatoryCard
    private var content: NSStackView { card.content }

    init(theme: Theme) {
        self.theme = theme
        card = ObservatoryCard(theme: theme, spacing: theme.observatory.cardPaddingVertical)
        super.init(frame: .zero)
        card.fill(self)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.processes.detail")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private var shown: ProcessesDetailModel?

    func show(_ model: ProcessesDetailModel?) {
        isHidden = model == nil
        guard let model, model != shown else { return }
        shown = model
        var views: [NSView] = [ObservatoryText.caption(model.caption, theme: theme)]
        if let command = model.command { views.append(commandBlock(command)) }
        views.append(facts(model.facts))
        let separator = ProcessesView.hairline(theme.observatory.separator)
        separator.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        views.append(separator)
        if let protection = model.protection {
            let reason = wrapping(protection, color: theme.text.secondary)
            reason.setAccessibilityIdentifier("smalti.processes.protection")
            views.append(reason)
        } else {
            views += model.actions.map(action)
        }
        content.setViews(views, in: .leading)
        for view in views { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        setAccessibilityLabel(model.caption)
        setAccessibilityValue(
            ([model.command].compactMap { $0 } + model.facts.map { "\($0.key) \($0.value)" }).joined(separator: " · "))
    }

    private func commandBlock(_ command: String) -> NSView {
        let tokens = theme.processes
        let label = NSTextField(wrappingLabelWithString: command)
        label.font = theme.monospacedFont(size: tokens.commandFontSize)
        label.textColor = theme.text.primary.nsColor
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byCharWrapping
        label.preferredMaxLayoutWidth =
            theme.observatory.sideColumnWidth - 2
            * (theme.observatory.cardPaddingHorizontal + tokens.commandBlockPadding)
        label.setAccessibilityIdentifier("smalti.processes.command")
        let block = NSView()
        block.wantsLayer = true
        block.layer?.cornerRadius = tokens.commandBlockRadius
        block.layer?.backgroundColor = tokens.commandBlock.nsColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(label)
        let padding = tokens.commandBlockPadding
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: block.topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -padding),
            label.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -padding),
        ])
        return block
    }

    private func facts(_ facts: [ProcessesDetailModel.Fact]) -> NSView {
        let tokens = theme.processes
        let rows = facts.map { fact -> NSView in
            let key = ObservatoryText.label(
                fact.key, .init(size: tokens.detailFontSize, color: theme.text.secondary), theme: theme)
            key.widthAnchor.constraint(equalToConstant: tokens.detailKeyWidth).isActive = true
            let style = ObservatoryText.Style(size: tokens.detailFontSize, color: theme.text.primary)
            let value =
                fact.isMono
                ? ObservatoryText.number(fact.value, style, theme: theme)
                : ObservatoryText.label(fact.value, style, theme: theme)
            value.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            return NSStackView(views: [key, value])
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.detailRowGap
        return stack
    }

    private func action(_ action: ProcessesDetailModel.Action) -> NSView {
        let tokens = theme.processes
        let key = KbdView(action.keys, theme: theme)
        key.widthAnchor.constraint(greaterThanOrEqualToConstant: tokens.actionKeyWidth).isActive = true
        let title = ObservatoryText.label(
            action.title, .init(size: tokens.detailFontSize, color: theme.text.primary), theme: theme)
        let stack = NSStackView(views: [key, title])
        stack.spacing = tokens.commandGap + 2
        stack.heightAnchor.constraint(equalToConstant: tokens.actionHeight).isActive = true
        return stack
    }

    private func wrapping(_ text: String, color: RGBAColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = theme.interfaceFont(size: theme.processes.detailFontSize)
        label.textColor = color.nsColor
        label.preferredMaxLayoutWidth = theme.observatory.sideColumnWidth - 2 * theme.observatory.cardPaddingHorizontal
        return label
    }
}

/// "Tus procesos · 312": the CPU line of the last two minutes, memory with the panes' part, and the note on hidden
/// processes and the refresh.
@MainActor
final class ProcessesTotalsView: NSView {
    private let theme: Theme
    private let card: ObservatoryCard
    private let caption: NSTextField
    private let cpuValue: NSTextField
    private let cpuCurve = Sparkline()
    private let memoryValue: NSTextField
    private let memoryBar = SplitBar()
    private let memoryNote: NSTextField
    private let footnote: NSTextField

    init(theme: Theme) {
        self.theme = theme
        let tokens = theme.observatory
        card = ObservatoryCard(theme: theme, spacing: tokens.spacing.system, height: .fill)
        caption = ObservatoryText.caption("", theme: theme)
        cpuValue = ObservatoryText.number(
            "", .init(size: tokens.systemRowSize, color: theme.text.primary), theme: theme)
        memoryValue = ObservatoryText.number(
            "", .init(size: tokens.systemRowSize, color: theme.text.primary), theme: theme)
        memoryNote = ObservatoryText.label(
            "", .init(size: tokens.footnoteSize, color: theme.text.secondary), theme: theme)
        footnote = ObservatoryText.label(
            "", .init(size: tokens.footnoteSize, color: theme.text.secondary), theme: theme)
        super.init(frame: .zero)
        card.fill(self)
        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 0
        footnote.preferredMaxLayoutWidth = tokens.sideColumnWidth - tokens.cardPaddingHorizontal * 2
        footnote.setAccessibilityIdentifier("smalti.processes.footnote")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        card.content.setViews(
            [
                caption, group([line("CPU", value: cpuValue), cpuCurve]),
                group([line(String(localized: "Memory"), value: memoryValue), memoryBar, memoryNote]), spacer,
                footnote,
            ], in: .leading)
        cpuCurve.translatesAutoresizingMaskIntoConstraints = false
        cpuCurve.heightAnchor.constraint(equalToConstant: tokens.sparklineHeight).isActive = true
        cpuCurve.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true
        memoryBar.translatesAutoresizingMaskIntoConstraints = false
        memoryBar.heightAnchor.constraint(equalToConstant: tokens.memoryBarHeight).isActive = true
        memoryBar.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.processes.totals")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func line(_ name: String, value: NSTextField) -> NSView {
        let label = ObservatoryText.label(
            name, .init(size: theme.observatory.systemRowSize, color: theme.text.primary), theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [label, spacer, value])
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = theme.observatory.spacing.systemGroup
        views.first?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func show(_ model: ProcessesTotalsModel) {
        let tokens = theme.observatory
        caption.attributedStringValue = ObservatoryText.caption(model.caption, theme: theme).attributedStringValue
        ObservatoryText.setText(cpuValue, model.cpu)
        ObservatoryText.setText(memoryValue, model.memory)
        ObservatoryText.setText(memoryNote, model.memoryNote)
        ObservatoryText.setText(footnote, model.footnote)
        cpuCurve.show(model.cpuHistory, maximum: nil, style: .init(line: tokens.cpu, width: tokens.sparklineWidth))
        memoryBar.show(
            [(model.panesFraction, theme.processes.panesMemory), (model.restFraction, theme.processes.restMemory)],
            track: tokens.memoryTrack)
        setAccessibilityLabel(model.caption)
        setAccessibilityValue([model.cpu, model.memory, model.memoryNote].joined(separator: " · "))
    }
}

/// "Resumen": how many ports and how many are open to the network, and what "todas" means.
@MainActor
final class PortsSummaryView: NSView {
    private let theme: Theme
    private let card: ObservatoryCard
    private let total: NSTextField
    private let open: NSTextField
    private let footnote: NSTextField

    init(theme: Theme) {
        self.theme = theme
        let tokens = theme.observatory
        card = ObservatoryCard(theme: theme, spacing: tokens.spacing.cardStack + 4, height: .fill)
        total = ObservatoryText.number("", .init(size: tokens.valueSize, color: theme.text.title), theme: theme)
        open = ObservatoryText.label("", .init(size: tokens.noteSize, color: theme.text.secondary), theme: theme)
        footnote = ObservatoryText.label(
            "", .init(size: tokens.footnoteSize, color: theme.text.secondary), theme: theme)
        super.init(frame: .zero)
        card.fill(self)
        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 0
        footnote.preferredMaxLayoutWidth = tokens.sideColumnWidth - tokens.cardPaddingHorizontal * 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        card.content.setViews(
            [ObservatoryText.caption(String(localized: "Summary"), theme: theme), total, open, spacer, footnote],
            in: .leading)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.ports.summary")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ model: PortsSummaryModel) {
        ObservatoryText.setText(total, model.total)
        ObservatoryText.setText(open, model.openToNetwork)
        ObservatoryText.setText(footnote, model.footnote)
        setAccessibilityValue([model.total, model.openToNetwork].joined(separator: " · "))
    }
}

/// A rounded bar split in colored parts, over a track.
@MainActor
private final class SplitBar: NSView {
    private var parts: [(Double, RGBAColor)] = []
    private var track = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    func show(_ parts: [(Double, RGBAColor)], track: RGBAColor) {
        self.parts = parts
        self.track = track
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        track.nsColor.setFill()
        clip.fill()
        clip.addClip()
        var x = 0.0
        for (share, color) in parts {
            color.nsColor.setFill()
            let width = bounds.width * min(max(share, 0), 1)
            NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
            x += width
        }
    }
}

/// The amber card that asks before SIGKILL, low and centered, over a 28 % shade (the approval card's surface).
@MainActor
final class ForceConfirmation: NSView {
    struct Content: Equatable {
        let title: String
        let body: String
        let command: String
    }

    private let theme: Theme
    private let card = NSView()
    private let title: NSTextField
    private let body: NSTextField
    private let command: NSTextField

    init(theme: Theme) {
        self.theme = theme
        let tokens = theme.processes
        let approval = theme.approvalCard
        title = ObservatoryText.label(
            "", .init(size: tokens.confirmTitleSize, color: approval.title, weight: theme.observatory.stripTitleWeight),
            theme: theme)
        body = NSTextField(wrappingLabelWithString: "")
        command = ObservatoryText.number(
            "", .init(size: tokens.commandFontSize, color: theme.text.secondary), theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(tokens.shadeAlpha).cgColor
        isHidden = true
        body.font = theme.interfaceFont(size: tokens.confirmBodySize)
        body.textColor = approval.emphasis.nsColor
        body.preferredMaxLayoutWidth = tokens.confirmWidth - 2 * tokens.confirmPadding
        layoutCard()
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func layoutCard() {
        let tokens = theme.processes
        let approval = theme.approvalCard
        card.wantsLayer = true
        card.layer?.cornerRadius = approval.cornerRadius
        card.layer?.backgroundColor = approval.background.nsColor.cgColor
        card.layer?.borderWidth = theme.chrome.hairlineWidth
        card.layer?.borderColor = approval.border.nsColor.cgColor
        card.layer?.shadowOpacity = Float(approval.shadowOpacity)
        card.layer?.shadowRadius = approval.shadowRadius
        card.layer?.shadowOffset = CGSize(width: 0, height: -approval.shadowOffsetY)
        let dot = StatusDot(diameter: approval.dotSize, style: .filled(approval.dot))
        let heading = NSStackView(views: [dot, title])
        heading.spacing = tokens.commandGap
        let keys = NSStackView(views: [
            hint("↵", String(localized: "force")), hint("esc", String(localized: "cancel")),
        ])
        keys.spacing = tokens.footerGap
        let stack = NSStackView(views: [heading, body, command, keys])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.confirmGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: tokens.confirmWidth),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -tokens.confirmBottom),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: tokens.confirmPadding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -tokens.confirmPadding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: tokens.confirmPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -tokens.confirmPadding),
        ])
        card.setAccessibilityElement(true)
        card.setAccessibilityRole(.group)
        card.setAccessibilityIdentifier("smalti.processes.confirm")
    }

    private func hint(_ keys: String, _ text: String) -> NSView {
        let label = ObservatoryText.label(
            text, .init(size: theme.processes.footerFontSize, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [KbdView(keys, theme: theme), label])
        stack.spacing = theme.processes.footerKeyGap
        return stack
    }

    func show(_ content: Content?) {
        isHidden = content == nil
        guard let content else { return }
        ObservatoryText.setText(title, content.title)
        body.stringValue = content.body
        ObservatoryText.setText(command, content.command)
        card.setAccessibilityLabel(content.title)
        card.setAccessibilityValue(content.body)
    }

    /// Clicks on the shade do nothing: the keys decide.
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : self }
}
