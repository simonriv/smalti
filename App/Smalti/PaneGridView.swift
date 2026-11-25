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
    /// Increases with every animation; only the latest one may unfreeze terminal content when it ends.
    private var animationGeneration = 0

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
    func render(_ state: TilingState, views: (PaneID) -> NSView?) {
        theme = state.theme
        let set = state.set
        let active = set.active
        let isRearrangement = workspace.map { $0.id == active.id && $0.tree != active.tree } ?? false
        workspace = active
        dropContainers(keeping: Set(set.workspaces.flatMap { $0.panes.map(\.id) }))
        attach(state, views: views)
        emptyState.isHidden = !active.panes.isEmpty
        let keys = state.config.keys
        emptyState.show(newPane: keys.chord(for: .paneNew), palette: keys.chord(for: .paletteOpen))
        place(animated: isRearrangement && !Motion.isReduced)
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

    private func attach(_ state: TilingState, views: (PaneID) -> NSView?) {
        let workspace = state.set.active
        let visible = Set(workspace.panes.map(\.id))
        for (pane, container) in containers where !visible.contains(pane) {
            container.removeFromSuperview()
        }
        let frames = workspace.tree?.frames(in: area, gap: theme.panel.gap) ?? [:]
        var context = HeaderContext(keymap: state.config.keys, home: state.home, now: .now)
        context.agentDetails = state.observatory?.paneDetails ?? [:]
        context.promptHeaders = state.promptHeaders
        for pane in workspace.panes.map(\.id) {
            let container = containers[pane] ?? newContainer(for: pane, at: frames[pane])
            if let view = views(pane) { container.embed(view) }
            if container.superview !== self { addSubview(container) }
            let header = workspace.panes.first { $0.id == pane }.map {
                PaneHeaderContent($0, index: state.set.paneIndex(of: pane), context: context)
            }
            container.apply(theme, isFocused: pane == workspace.focusedPane, header: header)
            container.showApproval(approvalContent(state, pane: pane, workspace: workspace.name))
            container.setAccessibilityLabel(workspace.index(of: pane).map { "Panel \($0)" })
        }
    }

    /// F7.5: the card of the pane's oldest waiting command, with the keys that decide it as the keymap binds them.
    private func approvalContent(_ state: TilingState, pane: PaneID, workspace: String) -> ApprovalCardContent? {
        guard let pending = state.approvals[pane], let first = pending.first else { return nil }
        return ApprovalCardContent(
            approval: first, count: pending.count, workspace: workspace, keys: state.config.keys, now: .now)
    }

    /// A new pane appears at its place; only the panes that already existed move.
    private func newContainer(for pane: PaneID, at frame: Rect?) -> PaneContainerView {
        let container = PaneContainerView(pane: pane, theme: theme)
        if let frame { container.frame = NSRect(frame) }
        containers[pane] = container
        return container
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
        animationGeneration += 1
        let generation = animationGeneration
        targets.forEach { container, frame in container.freezeContent(at: frame.size) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.motion.rearrangeDuration
            targets.forEach { container, frame in container.animator().frame = frame }
        } completionHandler: { [weak self] in
            // AppKit runs animation completions on the main thread.
            MainActor.assumeIsolated {
                guard let self, generation == self.animationGeneration else { return }
                self.containers.values.forEach { $0.unfreezeContent() }
            }
        }
    }

    private func paneClicked(by event: NSEvent) {
        guard event.window === window else { return }
        // Hit-test the whole window so a view above the grid (the ⌘K palette) keeps its clicks.
        guard let hit = window?.contentView?.hitTest(event.locationInWindow),
            let pane = containers.values.first(where: { $0.superview === self && hit.isDescendant(of: $0) })?.pane
        else { return }
        onPaneClicked?(pane)
    }
}

extension NSRect {
    init(_ rect: Rect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
