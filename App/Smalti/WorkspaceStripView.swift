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
    /// Last drawn model: terminal events publish often, and pills only change with workspaces.
    private var rendered: StripModel?

    /// Everything the strip draws; rebuilding happens only when it changes.
    private struct StripModel: Equatable {
        let pills: [Pill]
        let paletteChord: String
        let theme: Theme

        struct Pill: Equatable {
            let id: WorkspaceID
            let name: String
            let isActive: Bool
        }
    }

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
        let model = StripModel(
            pills: state.set.workspaces.map { .init(id: $0.id, name: $0.name, isActive: $0.id == state.set.activeID) },
            paletteChord: state.config.keys.chord(for: .paletteOpen)?.display ?? "", theme: state.theme)
        guard model != rendered else { return }
        rendered = model
        theme = model.theme
        let buttons: [NSView] =
            model.pills.map { pill in
                WorkspacePill(name: pill.name, isActive: pill.isActive, theme: theme) { [weak self] in
                    self?.onCommand?(.workspaceGo(pill.id))
                }
            } + [AddWorkspaceButton(theme: theme) { [weak self] in self?.onCommand?(.workspaceNew) }]
        pills.setViews(buttons, in: .leading)
        paletteHint.text = model.paletteChord
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.strip.bottomBorder.nsColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: theme.chrome.hairlineWidth).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// A workspace pill: status dot (neutral until F2) and name; the active one carries the accent ring and glow.
@MainActor
private final class WorkspacePill: NSView {
    private let action: () -> Void

    init(name: String, isActive: Bool, theme: Theme, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        style(isActive: isActive, theme: theme)
        layoutRow(name: name, isActive: isActive, theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.workspace")
        setAccessibilityLabel(name)
        setAccessibilityValue(isActive ? "active" : nil)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// The active pill carries the accent ring and glow, like the focused pane.
    private func style(isActive: Bool, theme: Theme) {
        wantsLayer = true
        layer?.cornerRadius = theme.strip.pillCornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = isActive ? theme.focus.ring.nsColor.cgColor : NSColor.clear.cgColor
        layer?.backgroundColor = isActive ? theme.focus.glow.nsColor.cgColor : NSColor.clear.cgColor
    }

    private func layoutRow(name: String, isActive: Bool, theme: Theme) {
        let strip = theme.strip
        let label = NSTextField(labelWithString: name)
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
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

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

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

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
    convenience init(diameter: Double, color: RGBAColor) {
        self.init(diameter: diameter, style: .filled(color))
    }

    init(diameter: Double, style: StatusDotStyle) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter), heightAnchor.constraint(equalToConstant: diameter),
        ])
        render(style)
    }

    /// Filled for working, waiting and failed; a hollow ring for a stopped agent.
    func render(_ style: StatusDotStyle) {
        switch style {
        case .filled(let color):
            layer?.backgroundColor = color.nsColor.cgColor
            layer?.borderWidth = 0
        case .hollow(let color, let width):
            layer?.backgroundColor = nil
            layer?.borderWidth = width
            layer?.borderColor = color.nsColor.cgColor
        }
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
