import AppKit
import SmaltiCore

/// Primary adapter that draws the active workspace: one `PaneContainerView` per pane at the rectangles the domain's
/// `LayoutTree.frames` returns. It holds no layout rules; it only places, styles and reports clicks.
@MainActor
final class PaneGridView: NSView {
    /// A click inside a pane asks to focus it (spec: "clic para enfocar").
    var onPaneClicked: ((PaneID) -> Void)?

    private var containers: [PaneID: PaneContainerView] = [:]
    private let emptyState: EmptyWorkspaceView
    private var theme: Theme
    private var workspace: Workspace?
    private var clickMonitor: Any?

    init(theme: Theme) {
        self.theme = theme
        emptyState = EmptyWorkspaceView(theme: theme)
        super.init(frame: .zero)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.paneGrid")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        clickMonitor.map(NSEvent.removeMonitor)
    }

    override var isFlipped: Bool { true }

    /// The domain's coordinate system: origin top-left, in points, the whole grid (padding is outside the view).
    var area: Rect { Rect(x: 0, y: 0, width: bounds.width, height: bounds.height) }

    /// Shows `set.active`. Containers of panes in other workspaces leave the view but stay alive (their processes
    /// keep running); containers of panes that no longer exist are dropped.
    func render(_ set: WorkspaceSet, config: SmaltiConfig, theme: Theme, views: (PaneID) -> NSView?) {
        self.theme = theme
        let active = set.active
        let isRearrangement = workspace.map { $0.id == active.id && $0.tree != active.tree } ?? false
        workspace = active
        dropContainers(keeping: Set(set.workspaces.flatMap { $0.panes.map(\.id) }))
        attach(active, views: views)
        emptyState.isHidden = !active.panes.isEmpty
        emptyState.show(newPane: config.keys.chord(for: .paneNew), palette: config.keys.chord(for: .paletteOpen))
        place(animated: isRearrangement && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func container(for pane: PaneID) -> PaneContainerView? { containers[pane] }

    override func layout() {
        super.layout()
        place(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
        guard window != nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.paneClicked(by: event) }
            return event
        }
    }

    private func attach(_ workspace: Workspace, views: (PaneID) -> NSView?) {
        let visible = Set(workspace.panes.map(\.id))
        for (pane, container) in containers where !visible.contains(pane) {
            container.removeFromSuperview()
        }
        for pane in workspace.panes.map(\.id) {
            let container = containers[pane] ?? PaneContainerView(pane: pane, theme: theme)
            containers[pane] = container
            if let view = views(pane) { container.embed(view) }
            if container.superview !== self { addSubview(container) }
            container.apply(theme, isFocused: pane == workspace.focusedPane)
        }
    }

    private func dropContainers(keeping alive: Set<PaneID>) {
        for (pane, container) in containers where !alive.contains(pane) {
            container.removeFromSuperview()
            containers[pane] = nil
        }
    }

    private func place(animated: Bool) {
        guard let frames = workspace?.tree?.frames(in: area, gap: theme.panel.gap) else { return }
        let targets = frames.compactMap { pane, rect in containers[pane].map { ($0, NSRect(rect)) } }
        guard animated else {
            targets.forEach { container, frame in container.frame = frame }
            return
        }
        animate(targets)
    }

    /// Only the frames move; each terminal jumps to its final size first so the Metal surface never stretches.
    private func animate(_ targets: [(PaneContainerView, NSRect)]) {
        targets.forEach { container, frame in container.freezeContent(at: frame.size) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.motion.rearrangeDuration
            targets.forEach { container, frame in container.animator().frame = frame }
        } completionHandler: {
            MainActor.assumeIsolated { targets.forEach { container, _ in container.unfreezeContent() } }
        }
    }

    private func paneClicked(by event: NSEvent) {
        guard event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = containers.values.first(where: { $0.superview === self && $0.frame.contains(point) })
        else { return }
        onPaneClicked?(hit.pane)
    }
}

extension NSRect {
    init(_ rect: Rect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
