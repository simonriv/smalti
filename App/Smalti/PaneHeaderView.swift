import AppKit
import SmaltiCore

/// Pane header (30 pt, Inter 11.5): agent state dot, process in the title color, directory, the agent's detail
/// ("te espera · 2m" in amber, "error · 3m" in red, the session's lifetime otherwise) and the shortcut.
@MainActor
final class PaneHeaderView: NSView {
    private var dot: StatusDot
    private let process = NSTextField(labelWithString: "")
    private let directory = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
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
        row.setViews([dot, process, directory, spacer, detail, shortcut], in: .leading)
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
        shortcut.text = header.shortcut
        setAccessibilityLabel(header.process)
        setAccessibilityValue(header.directory)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.header.bottomBorder.nsColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: theme.chrome.hairlineWidth).fill()
    }
}
