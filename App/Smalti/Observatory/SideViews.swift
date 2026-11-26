import AppKit
import SmaltiCore

/// "Modelos locales · Ollama": loaded models first, then those on disk, or why there are none.
@MainActor
final class LocalModelsView: NSView {
    private let card: ObservatoryCard
    private var content: NSStackView { card.content }
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        card = ObservatoryCard(theme: theme, spacing: theme.observatory.spacing.localModels)
        super.init(frame: .zero)
        card.fill(self)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.observatory.localModels")
    }

    func show(_ figures: LocalModelsFigures) {
        let caption = ObservatoryText.caption("Modelos locales · Ollama", theme: theme)
        switch figures {
        case .message(let text):
            content.setViews(
                [
                    caption,
                    ObservatoryText.label(
                        text, .init(size: theme.observatory.noteSize, color: theme.text.secondary), theme: theme),
                ],
                in: .leading)
            setAccessibilityValue(text)
        case .models(let rows):
            var views: [NSView] = [caption]
            for (index, row) in rows.enumerated() {
                if index > 0 { views.append(separator()) }
                views.append(model(row))
            }
            content.setViews(views, in: .leading)
            setAccessibilityValue(rows.map { "\($0.name) \($0.status)" }.joined(separator: ", "))
        }
    }

    private func model(_ row: LocalModelsFigures.Row) -> NSView {
        let tokens = theme.observatory
        let name = ObservatoryText.label(
            row.name,
            .init(size: tokens.modelNameSize, color: row.isLoaded ? theme.text.title : theme.header.directory),
            theme: theme)
        let status = ObservatoryText.label(
            row.status, .init(size: tokens.noteSize, color: row.isLoaded ? theme.agent.working : theme.text.secondary),
            theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let top = NSStackView(views: [name, spacer, status])
        let detail = ObservatoryText.number(
            row.detail, .init(size: tokens.noteSize, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [top, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = theme.observatory.spacing.modelLines
        top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = theme.observatory.separator.nsColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}

/// "Sistema · <Mac>": CPU and GPU curves, unified memory and its split, and where the data comes from.
@MainActor
final class SystemView: NSView {
    private let card: ObservatoryCard
    private var content: NSStackView { card.content }
    private let theme: Theme
    private let title: NSTextField
    private let cpuValue: NSTextField
    private let gpuValue: NSTextField
    private let memoryValue: NSTextField
    private let split: NSTextField
    private let cpuCurve = Sparkline()
    private let gpuCurve = Sparkline()
    private let memoryBar = MemoryBar()
    /// F7: names Claude Code's telemetry once some arrived.
    private let footnote: NSTextField

    /// CPU and GPU curves are percentages: their scale tops at 100, not at the highest sample.
    private static let percentScale = 100.0

    static let footnote = ObservatoryCopy.spanish.footnote  // T9

    init(theme: Theme) {
        self.theme = theme
        card = ObservatoryCard(theme: theme, spacing: theme.observatory.spacing.system, height: .fill)
        let tokens = theme.observatory
        title = ObservatoryText.caption("Sistema", theme: theme)
        cpuValue = ObservatoryText.number(
            "", .init(size: tokens.systemRowSize, color: theme.text.primary), theme: theme)
        gpuValue = ObservatoryText.number(
            "", .init(size: tokens.systemRowSize, color: theme.text.primary), theme: theme)
        memoryValue = ObservatoryText.number(
            "", .init(size: tokens.systemRowSize, color: theme.text.primary), theme: theme)
        split = ObservatoryText.label("", .init(size: tokens.footnoteSize, color: theme.text.secondary), theme: theme)
        footnote = ObservatoryText.label(
            Self.footnote, .init(size: tokens.footnoteSize, color: theme.text.secondary), theme: theme)
        super.init(frame: .zero)
        card.fill(self)
        footnote.setAccessibilityIdentifier("smalti.observatory.footnote")
        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 0
        footnote.preferredMaxLayoutWidth = tokens.sideColumnWidth - tokens.cardPaddingHorizontal * 2
        let memory = group([line("Memoria unificada", value: memoryValue), memoryBar, split])
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        content.setViews(
            [
                title, group([line("CPU", value: cpuValue), cpuCurve]),
                group([line("GPU", value: gpuValue), gpuCurve]),
                memory, spacer, footnote,
            ], in: .leading)
        for curve in [cpuCurve, gpuCurve] {
            curve.translatesAutoresizingMaskIntoConstraints = false
            curve.heightAnchor.constraint(equalToConstant: tokens.sparklineHeight).isActive = true
            curve.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        memoryBar.translatesAutoresizingMaskIntoConstraints = false
        memoryBar.heightAnchor.constraint(equalToConstant: tokens.memoryBarHeight).isActive = true
        memoryBar.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.observatory.system")
    }

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

    func show(_ figures: SystemFigures, cpuHistory: [Double], gpuHistory: [Double], footnote text: String) {
        let tokens = theme.observatory
        ObservatoryText.setText(footnote, text)
        title.attributedStringValue = ObservatoryText.caption(figures.title, theme: theme).attributedStringValue
        ObservatoryText.setText(cpuValue, figures.cpu)
        ObservatoryText.setText(gpuValue, figures.gpu)
        ObservatoryText.setText(memoryValue, figures.memory)
        ObservatoryText.setText(split, figures.split)
        cpuCurve.show(
            cpuHistory, maximum: Self.percentScale, style: .init(line: tokens.cpu, width: tokens.sparklineWidth))
        gpuCurve.show(
            gpuHistory, maximum: Self.percentScale, style: .init(line: tokens.gpu, width: tokens.sparklineWidth))
        memoryBar.show(figures.shares, theme: theme)
        setAccessibilityLabel(figures.title)
        setAccessibilityValue([figures.cpu, figures.gpu, figures.memory, figures.split].joined(separator: " · "))
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}

/// The unified-memory bar: model, agents and the rest, over the installed memory.
@MainActor
private final class MemoryBar: NSView {
    private var shares = SystemFigures.Shares(model: 0, agents: 0, rest: 0)
    private var colors: [NSColor] = []
    private var track = NSColor.clear

    func show(_ shares: SystemFigures.Shares, theme: Theme) {
        self.shares = shares
        colors = [theme.observatory.memoryModel, theme.accent, theme.observatory.memoryRest].map(\.nsColor)
        track = theme.observatory.memoryTrack.nsColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        track.setFill()
        clip.fill()
        clip.addClip()
        var x = 0.0
        for (share, color) in zip([shares.model, shares.agents, shares.rest], colors) {
            color.setFill()
            let width = bounds.width * min(max(share, 0), 1)
            NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
            x += width
        }
    }
}
