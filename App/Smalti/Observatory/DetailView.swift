import AppKit
import SmaltiCore

/// The card under the table: the selected session's latest tools, and its output per minute over the last hour.
@MainActor
final class DetailView: NSView {
    private let card: ObservatoryCard
    private var content: NSStackView { card.content }
    private let theme: Theme
    private let activityTitle: NSTextField
    private let activityRows = NSStackView()
    private let chart = Sparkline()
    private let compaction: NSTextField
    private let empty: NSTextField
    private var activity: NSStackView?

    static let noActivity = "Sin actividad en la última hora"

    init(theme: Theme) {
        self.theme = theme
        card = ObservatoryCard(theme: theme, spacing: theme.observatory.spacing.detailStack, height: .fill)
        let tokens = theme.observatory
        activityTitle = ObservatoryText.caption("Actividad", theme: theme)
        compaction = ObservatoryText.label("", size: tokens.noteSize, color: theme.text.secondary, theme: theme)
        empty = ObservatoryText.label(Self.noActivity, size: tokens.noteSize, color: theme.text.secondary, theme: theme)
        super.init(frame: .zero)
        card.fill(self)
        content.orientation = .horizontal
        content.alignment = .top
        content.distribution = .fill
        content.spacing = tokens.spacing.detailColumns
        activityRows.orientation = .vertical
        activityRows.alignment = .leading
        activityRows.spacing = tokens.activityRowGap
        let left = column([activityTitle, activityRows], identifier: "smalti.observatory.activity")
        activity = left
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: tokens.chartHeight).isActive = true
        chart.setAccessibilityElement(true)
        chart.setAccessibilityRole(.image)
        chart.setAccessibilityIdentifier("smalti.observatory.chart")
        let right = column(
            [ObservatoryText.caption("Tokens por minuto · última hora", theme: theme), chart, empty, compaction],
            identifier: "smalti.observatory.output")
        content.setViews([left, right], in: .leading)
        left.widthAnchor.constraint(equalTo: right.widthAnchor, multiplier: tokens.spacing.detailRatio).isActive = true
        chart.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
    }

    private func column(_ views: [NSView], identifier: String) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = theme.observatory.spacing.detailStack
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityIdentifier(identifier)
        return stack
    }

    func show(_ detail: ObservatoryReport.Detail?, timeZone: TimeZone) {
        guard let detail else {
            activityTitle.attributedStringValue =
                ObservatoryText.caption("Actividad", theme: theme).attributedStringValue
            activityRows.setViews([], in: .leading)
            chart.isHidden = true
            empty.isHidden = false
            compaction.stringValue = ""
            return
        }
        activityTitle.attributedStringValue = ObservatoryText.caption(detail.title, theme: theme).attributedStringValue
        activity?.setAccessibilityValue(detail.title)
        activityRows.setViews(detail.tools.map { row(for: $0, timeZone: timeZone) }, in: .leading)
        let hasOutput = detail.peak != nil
        chart.isHidden = !hasOutput
        empty.isHidden = hasOutput
        chart.show(
            detail.outputPerMinute.map(Double.init), maximum: nil, style: chartStyle(detail.peak, timeZone: timeZone))
        chart.setAccessibilityValue(
            detail.peak.map { ObservatoryTexts.chartPeak($0, timeZone: timeZone) } ?? Self.noActivity)
        ObservatoryText.setText(compaction, detail.compaction)
    }

    private func chartStyle(_ peak: OutputPeak?, timeZone: TimeZone) -> Sparkline.Style {
        let tokens = theme.observatory
        var style = Sparkline.Style(line: theme.accent, width: tokens.chartLineWidth, fill: theme.focus.glow)
        style.grid = [(1, tokens.chartGrid), (0.5, tokens.chartGridFaint)]
        if let peak {
            style.peak = (
                tokens.chartPeakRadius, ObservatoryTexts.chartPeak(peak, timeZone: timeZone),
                theme.interfaceFont(size: tokens.spacing.chartLabelSize), theme.header.directory
            )
        }
        return style
    }

    private func row(for tool: RecentTool, timeZone: TimeZone) -> NSView {
        let tokens = theme.observatory
        let size = tokens.activityFontSize
        let result = ObservatoryTexts.result(of: tool)
        let time = ObservatoryText.number(
            ObservatoryFormat.clock(tool.startedAt, timeZone: timeZone), size: size, color: theme.text.secondary,
            theme: theme)
        let name = ObservatoryText.number(tool.name, size: size, color: theme.accent, theme: theme)
        let summary = ObservatoryText.number(tool.summary, size: size, color: theme.text.primary, theme: theme)
        let outcome = ObservatoryText.number(
            result.text, size: size, color: result.isFailure ? theme.agent.failed : theme.agent.working, theme: theme)
        [time, name].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        time.widthAnchor.constraint(equalToConstant: tokens.activityTimeWidth).isActive = true
        name.widthAnchor.constraint(equalToConstant: tokens.activityToolWidth).isActive = true
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let line = NSStackView(views: [time, name, summary, outcome])
        line.spacing = tokens.spacing.activityColumns
        return line
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
