import AppKit
import SmaltiCore

/// Bottom bar (28 pt): `<workspace> · N paneles · <layout>`, or a status message in its place. The right side
/// (models, RAM, GPU, tokens) arrives in F3.
@MainActor
final class StatusBarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.statusBar.padding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -theme.statusBar.padding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
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
        label.stringValue = state.message?.text ?? Self.summary(of: state.set.active)
        setAccessibilityValue(label.stringValue)
        needsDisplay = true
    }

    /// "solen · 3 paneles · dwindle", as in `Main.dc.html`.
    static func summary(of workspace: Workspace) -> String {
        let count = workspace.panes.count
        return "\(workspace.name) · \(count) \(count == 1 ? "panel" : "paneles") · \(workspace.layout.statusName)"
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.statusBar.topBorder.nsColor.setFill()
        NSRect(x: 0, y: bounds.maxY - theme.panel.borderWidth, width: bounds.width, height: theme.panel.borderWidth)
            .fill()
    }
}
