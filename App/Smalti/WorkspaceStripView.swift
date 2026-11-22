import AppKit
import SmaltiCore

/// Top strip (40 pt, `Main.dc.html`): one pill per workspace, the "+" button and the `⌘K` hint. Empty space drags
/// the window. Clicks are a secondary path: every action here also has a shortcut and a palette entry.
@MainActor
final class WorkspaceStripView: NSView {
    var onCommand: ((CommandID) -> Void)?

    private let pills = NSStackView()
    private let paletteHint: KbdView
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        paletteHint = KbdView("", theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        pills.orientation = .horizontal
        pills.spacing = theme.strip.pillGap
        for view in [pills, paletteHint] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            pills.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.strip.paddingLeading),
            pills.centerYAnchor.constraint(equalTo: centerYAnchor),
            paletteHint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.strip.paddingTrailing),
            paletteHint.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.dragStrip")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func render(_ state: TilingState) {
        theme = state.theme
        let buttons: [NSView] =
            state.set.workspaces.map { workspace in
                WorkspacePill(workspace, isActive: workspace.id == state.set.activeID, theme: theme) { [weak self] in
                    self?.onCommand?(.workspaceGo(workspace.id))
                }
            } + [AddWorkspaceButton(theme: theme) { [weak self] in self?.onCommand?(.workspaceNew) }]
        pills.setViews(buttons, in: .leading)
        paletteHint.text = state.config.keys.chord(for: .paletteOpen)?.display ?? ""
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.strip.bottomBorder.nsColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: theme.panel.borderWidth).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// A workspace pill: status dot (neutral until F2) and name; the active one carries the accent ring and glow.
@MainActor
private final class WorkspacePill: NSView {
    private let action: () -> Void

    init(_ workspace: Workspace, isActive: Bool, theme: Theme, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let strip = theme.strip
        wantsLayer = true
        layer?.cornerRadius = strip.pillCornerRadius
        layer?.borderWidth = theme.panel.borderWidth
        layer?.borderColor = isActive ? theme.focus.ring.nsColor.cgColor : NSColor.clear.cgColor
        layer?.backgroundColor = isActive ? theme.focus.glow.nsColor.cgColor : NSColor.clear.cgColor
        let label = NSTextField(labelWithString: workspace.name)
        label.font = theme.interfaceFont(size: strip.fontSize, weight: strip.fontWeight)
        label.textColor = (isActive ? strip.activeText : strip.inactiveText).nsColor
        let row = NSStackView(views: [StatusDot(diameter: strip.dotSize, color: strip.dot), label])
        row.spacing = strip.labelGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: strip.pillHeight),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: strip.pillPadding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -strip.pillPadding),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.workspace")
        setAccessibilityLabel(workspace.name)
        setAccessibilityValue(isActive ? "active" : nil)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { action() }
}

/// "+" (new workspace): a square as tall as a pill with a thin cross.
@MainActor
private final class AddWorkspaceButton: NSView {
    private let action: () -> Void
    private let theme: Theme

    init(theme: Theme, action: @escaping () -> Void) {
        self.action = action
        self.theme = theme
        super.init(frame: .zero)
        let side = theme.strip.pillHeight
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.newWorkspace")
        setAccessibilityLabel("Nuevo workspace")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let size = theme.strip.addButtonIconSize
        let icon = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: icon.midX, y: icon.minY))
        cross.line(to: NSPoint(x: icon.midX, y: icon.maxY))
        cross.move(to: NSPoint(x: icon.minX, y: icon.midY))
        cross.line(to: NSPoint(x: icon.maxX, y: icon.midY))
        cross.lineWidth = theme.strip.addButtonIconStroke
        theme.strip.addButtonColor.nsColor.setStroke()
        cross.stroke()
    }

    override func mouseDown(with event: NSEvent) { action() }
}

/// Status dot. Neutral in F1; F2 colors it by agent state (working, waiting, error, stopped).
@MainActor
final class StatusDot: NSView {
    init(diameter: Double, color: RGBAColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        layer?.backgroundColor = color.nsColor.cgColor
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter), heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
