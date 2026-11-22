import AppKit
import SmaltiCore

/// Hint for a workspace with no panes, centred in the pane area (decided by Simón, 2026-11-22): "Workspace vacío"
/// and, below, "⌘D nuevo panel · ⌘K comandos" with the shortcuts drawn as `kbd`. No buttons, as everywhere else.
final class EmptyWorkspaceView: NSView {
    private let title = NSTextField(labelWithString: "Workspace vacío")
    private let newPaneKey: KbdView
    private let paletteKey: KbdView
    private let stack = NSStackView()

    init(theme: Theme) {
        newPaneKey = KbdView("", theme: theme)
        paletteKey = KbdView("", theme: theme)
        super.init(frame: .zero)
        let font = theme.interfaceFont(size: theme.emptyState.fontSize)
        let color = theme.emptyState.text.nsColor
        title.font = font
        title.textColor = color
        let shortcuts = NSStackView(views: [
            newPaneKey, Self.label(" nuevo panel · ", font: font, color: color),
            paletteKey, Self.label(" comandos", font: font, color: color),
        ])
        shortcuts.spacing = 0
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = theme.emptyState.lineGap
        stack.setViews([title, shortcuts], in: .center)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier("smalti.emptyWorkspace")
        setAccessibilityLabel("Workspace vacío")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Shortcuts come from the keymap, so a rebinding in config.toml shows here too.
    func show(newPane: KeyChord?, palette: KeyChord?) {
        newPaneKey.text = newPane?.display ?? ""
        paletteKey.text = palette?.display ?? ""
    }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }
}
