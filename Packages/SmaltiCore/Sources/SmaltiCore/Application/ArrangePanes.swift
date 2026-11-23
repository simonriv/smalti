public enum FocusTarget: Equatable, Sendable {
    case direction(Direction)
    /// Position in the active workspace, counting from 1.
    case index(Int)
}

/// Moves focus within the active workspace. Without a target pane it does nothing.
@MainActor
public struct FocusPane {
    public init() {}

    public func execute(_ target: FocusTarget, geometry: LayoutGeometry, in set: inout WorkspaceSet) {
        guard let pane = resolve(target, geometry: geometry, in: set.active) else { return }
        set = set.updating(set.activeID) { $0.focusing(pane) }
    }

    private func resolve(_ target: FocusTarget, geometry: LayoutGeometry, in workspace: Workspace) -> PaneID? {
        switch target {
        case .direction(let direction):
            neighbor(toward: direction, geometry: geometry, in: workspace)
        case .index(let position):
            workspace.panes.indices.contains(position - 1) ? workspace.panes[position - 1].id : nil
        }
    }
}

/// Exchanges the focused pane with its neighbor; focus stays with the moved pane.
@MainActor
public struct SwapPane {
    public init() {}

    public func execute(toward direction: Direction, geometry: LayoutGeometry, in set: inout WorkspaceSet) {
        let workspace = set.active
        guard let focused = workspace.focusedPane,
            let other = neighbor(toward: direction, geometry: geometry, in: workspace)
        else { return }
        set = set.updating(set.activeID) { $0.swapping(focused, other) }
    }
}

/// Moves the focused pane's edge by one step.
@MainActor
public struct ResizePane {
    public init() {}

    public func execute(toward direction: Direction, geometry: LayoutGeometry, in set: inout WorkspaceSet) {
        guard let focused = set.active.focusedPane else { return }
        let request = ResizeRequest(pane: focused, direction: direction, step: ResizeRequest.defaultStep)
        set = set.updating(set.activeID) { $0.resizing(request, within: geometry) }
    }
}

@MainActor
public struct EqualizePanes {
    public init() {}

    public func execute(in set: inout WorkspaceSet) {
        set = set.updating(set.activeID) { $0.equalized() }
    }
}

@MainActor
public struct SwitchLayout {
    public init() {}

    public func execute(to layout: any LayoutStrategy, in set: inout WorkspaceSet) {
        set = set.updating(set.activeID) { $0.switchingLayout(to: layout) }
    }
}

/// The pane next to the focused one in `direction`, if any.
private func neighbor(toward direction: Direction, geometry: LayoutGeometry, in workspace: Workspace) -> PaneID? {
    guard let focused = workspace.focusedPane else { return nil }
    return workspace.tree?.neighbor(of: focused, toward: direction, in: geometry.area, gap: geometry.gap)
}
