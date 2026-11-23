import AppKit
import SmaltiCore

/// Bottom bar (28 pt): `<workspace> · N paneles · <layout>`, or a status message in its place; on the right, the
/// observatory's figures: loaded local model, RAM, GPU and today's tokens (Main.dc.html).
@MainActor
final class StatusBarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let figures = NSStackView()
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        figures.orientation = .horizontal
        figures.spacing = theme.statusBar.gap
        figures.translatesAutoresizingMaskIntoConstraints = false
        figures.setAccessibilityElement(true)
        figures.setAccessibilityRole(.staticText)
        figures.setAccessibilityIdentifier("smalti.statusFigures")
        addSubview(figures)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.statusBar.padding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: figures.leadingAnchor, constant: -theme.statusBar.gap),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            figures.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.statusBar.padding),
            figures.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier("smalti.statusBar")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func render(_ state: TilingState) {
        theme = state.theme
        label.font = theme.interfaceFont(size: theme.statusBar.fontSize)
        label.textColor = theme.statusBar.text.nsColor
        label.stringValue = state.message?.text ?? state.set.active.statusLine
        setAccessibilityValue(label.stringValue)
        showFigures(state.observatory?.statusFigures)
        needsDisplay = true
    }

    /// Model (only with one loaded), RAM, GPU, then today's tokens a step brighter.
    private func showFigures(_ values: StatusFigures?) {
        guard let values else {
            figures.setViews([], in: .leading)
            return
        }
        let texts = [values.localModel, values.ram, values.gpu].compactMap { $0 }
        let font = theme.interfaceFont(size: theme.statusBar.fontSize)
        let views =
            texts.map { figure($0, font: font, color: theme.statusBar.text) }
            + [figure(values.todayTokens, font: font, color: theme.statusBar.todayTokens)]
        figures.setViews(views, in: .leading)
        figures.setAccessibilityValue((texts + [values.todayTokens]).joined(separator: " · "))
    }

    private func figure(_ text: String, font: NSFont, color: RGBAColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color.nsColor
        return field
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.statusBar.topBorder.nsColor.setFill()
        NSRect(
            x: 0, y: bounds.maxY - theme.chrome.hairlineWidth, width: bounds.width, height: theme.chrome.hairlineWidth
        )
        .fill()
    }
}
