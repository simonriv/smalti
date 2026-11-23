import AppKit
import SmaltiCore

/// Pane header (30 pt, Inter 11.5): agent state dot, process in the title color, directory (with the model family),
/// "ctx 41%" and its bar while the agent works, the agent's detail ("te espera · 2m" in amber, "error · 3m" in red,
/// the session's lifetime otherwise) and the shortcut.
@MainActor
final class PaneHeaderView: NSView {
    private var dot: StatusDot
    private let process = NSTextField(labelWithString: "")
    private let directory = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "")
    private let contextBar = ContextBar()
    private let shortcut: KbdView
    private let row = NSStackView()
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        dot = StatusDot(diameter: theme.header.dotSize, color: theme.header.dot)
        shortcut = KbdView("", theme: theme)
        super.init(frame: .zero)
        layoutRow()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.paneHeader")
    }

    /// dot · process · directory (truncates first) · flexible space · shortcut.
    private func layoutRow() {
        directory.lineBreakMode = .byTruncatingHead
        directory.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        dot.setAccessibilityElement(true)
        dot.setAccessibilityIdentifier("smalti.paneStatus")
        detail.setAccessibilityIdentifier("smalti.paneDetail")
        contextLabel.setAccessibilityIdentifier("smalti.paneContext")
        contextBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contextBar.widthAnchor.constraint(equalToConstant: theme.header.contextBarWidth),
            contextBar.heightAnchor.constraint(equalToConstant: theme.header.contextBarHeight),
        ])
        row.setViews([dot, process, directory, spacer, contextLabel, contextBar, detail, shortcut], in: .leading)
        row.spacing = theme.header.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.header.padding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.header.padding),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ header: PaneHeaderContent, theme: Theme) {
        self.theme = theme
        let size = theme.header.fontSize
        process.font = theme.interfaceFont(size: size, weight: theme.header.processFontWeight)
        process.textColor = theme.text.title.nsColor
        process.stringValue = header.process
        directory.font = theme.interfaceFont(size: size)
        directory.textColor = theme.header.directory.nsColor
        directory.stringValue = header.directory
        dot.render(theme.statusDot(for: header.status))
        dot.setAccessibilityValue(header.status?.rawValue ?? "none")
        detail.font = theme.interfaceFont(size: size)
        detail.stringValue = header.detail?.text ?? ""
        detail.textColor = header.detail.map { theme.color(for: $0.tone) }?.nsColor
        detail.isHidden = header.detail == nil
        showContext(header.context, theme: theme)
        shortcut.text = header.shortcut
        setAccessibilityLabel(header.process)
        setAccessibilityValue(header.directory)
        needsDisplay = true
    }

    private func showContext(_ load: ContextLoad?, theme: Theme) {
        guard case .percent(let value) = load else {
            contextLabel.isHidden = true
            contextBar.isHidden = true
            return
        }
        contextLabel.isHidden = false
        contextBar.isHidden = false
        contextLabel.font = theme.interfaceFont(size: theme.header.fontSize)
        contextLabel.textColor = theme.header.directory.nsColor
        contextLabel.stringValue = "ctx \(ObservatoryFormat.percent(value))"
        contextLabel.setAccessibilityValue(contextLabel.stringValue)
        contextBar.show(
            fraction: Double(value) / 100, fill: load?.isHigh == true ? theme.agent.waiting : theme.accent,
            track: theme.header.contextBarTrack)
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.header.bottomBorder.nsColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: theme.chrome.hairlineWidth).fill()
    }
}

/// A thin rounded bar filled to a fraction: the context load in a header (and in the observatory's table).
final class ContextBar: NSView {
    private var fraction = 0.0
    private var fill = NSColor.clear
    private var track = NSColor.clear

    func show(fraction: Double, fill: RGBAColor, track: RGBAColor) {
        self.fraction = min(max(fraction, 0), 1)
        self.fill = fill.nsColor
        self.track = track.nsColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        track.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        fill.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height), xRadius: radius,
            yRadius: radius
        ).fill()
    }
}
