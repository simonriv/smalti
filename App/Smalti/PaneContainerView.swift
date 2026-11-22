import AppKit
import SmaltiCore

/// Rounded panel that hosts one terminal view.
final class PaneContainerView: NSView {
    init(theme: Theme) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.panel.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = theme.panel.border.nsColor.cgColor
        layer?.backgroundColor = theme.panel.background.nsColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.pane")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func embed(_ terminalView: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
