import Foundation

/// A named set of panes, the layout that arranges them and which one has focus.
///
/// Invariant: `tree` holds exactly the panes of `panes`, in order (`nil` when
/// there are none), and `focusedPane` is one of them (`nil` only when empty).
/// Structural changes (add, remove, switch layout) rebuild `tree` from the
/// layout and drop manual ratios; swap, resize and equalize keep the tree.
public struct Workspace: Sendable, Equatable {
    public let id: WorkspaceID
    public private(set) var name: String
    public let rootDirectory: WorkingDirectory
    public private(set) var panes: [Pane]
    public private(set) var layout: any LayoutStrategy
    public private(set) var tree: LayoutTree?
    public private(set) var focusedPane: PaneID?

    public static func empty(
        name: String, rootDirectory: WorkingDirectory, layout: any LayoutStrategy
    ) -> Workspace {
        Workspace(
            id: WorkspaceID(), name: name, rootDirectory: rootDirectory, panes: [],
            layout: layout, tree: nil, focusedPane: nil)
    }

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rootDirectory == rhs.rootDirectory
            && lhs.panes == rhs.panes && lhs.layout.id == rhs.layout.id && lhs.tree == rhs.tree
            && lhs.focusedPane == rhs.focusedPane
    }

    public func contains(_ pane: PaneID) -> Bool {
        index(of: pane) != nil
    }

    /// Position of `pane` counting from 1.
    public func index(of pane: PaneID) -> Int? {
        panes.firstIndex { $0.id == pane }.map { $0 + 1 }
    }

    /// The directory of the focused pane, or the workspace root when empty.
    public var directoryForNewPane: WorkingDirectory {
        panes.first { $0.id == focusedPane }?.workingDirectory ?? rootDirectory
    }

    public func adding(_ pane: Pane) -> Workspace {
        guard !contains(pane.id) else { return self }
        var updated = self
        updated.panes.append(pane)
        updated.focusedPane = pane.id
        return updated.rebuildingTree()
    }

    public func removing(_ pane: PaneID) -> Workspace {
        guard let position = panes.firstIndex(where: { $0.id == pane }) else { return self }
        var updated = self
        updated.panes.remove(at: position)
        if focusedPane == pane {
            let neighbor = position > 0 ? position - 1 : position
            updated.focusedPane = updated.panes.indices.contains(neighbor) ? updated.panes[neighbor].id : nil
        }
        return updated.rebuildingTree()
    }

    public func switchingLayout(to layout: any LayoutStrategy) -> Workspace {
        var updated = self
        updated.layout = layout
        return updated.rebuildingTree()
    }

    public func focusing(_ pane: PaneID) -> Workspace {
        guard contains(pane) else { return self }
        var updated = self
        updated.focusedPane = pane
        return updated
    }

    public func swapping(_ a: PaneID, _ b: PaneID) -> Workspace {
        guard let first = panes.firstIndex(where: { $0.id == a }),
            let second = panes.firstIndex(where: { $0.id == b })
        else { return self }
        var updated = self
        updated.panes.swapAt(first, second)
        updated.tree = tree?.swapping(a, b)
        return updated
    }

    public func resizing(_ request: ResizeRequest, within geometry: LayoutGeometry) -> Workspace {
        guard contains(request.pane) else { return self }
        var updated = self
        updated.tree = tree?.resizing(request, within: geometry)
        return updated
    }

    public func equalized() -> Workspace {
        var updated = self
        updated.tree = tree?.equalized()
        return updated
    }

    public func applying(_ event: TerminalEvent, to pane: PaneID) -> Workspace {
        guard let position = panes.firstIndex(where: { $0.id == pane }) else { return self }
        var updated = self
        updated.panes[position] = panes[position].applying(event)
        return updated
    }

    /// Puts back a saved split tree, ratios included, when it holds exactly these panes in this order; otherwise
    /// keeps the tree the layout built.
    public func withSavedTree(_ saved: LayoutTree) -> Workspace {
        guard saved.panes == panes.map(\.id) else { return self }
        var updated = self
        updated.tree = saved
        return updated
    }

    public func applying(_ event: TerminalEvent, to pane: PaneID, at date: Date) -> Workspace {
        replacing(pane) { $0.applying(event, at: date) }
    }

    /// F6: the session a pane's harness captured (or the fallback without an id).
    public func binding(_ binding: HarnessBinding, to pane: PaneID) -> Workspace {
        replacing(pane) { $0.binding(binding) }
    }

    public func applying(_ event: AgentEvent) -> (Workspace, AttentionReason?) {
        var attention: AttentionReason?
        let updated = replacing(event.pane) { pane in
            let result = pane.applying(event)
            attention = result.1
            return result.0
        }
        return (updated, attention)
    }

    /// Its most urgent agent (error > te espera > trabajando > detenido); nil without agents.
    public var agentStatus: AgentStateKind? {
        AgentStateKind.mostUrgent(panes.compactMap(\.agent?.state.kind))
    }

    private func replacing(_ pane: PaneID, _ transform: (Pane) -> Pane) -> Workspace {
        guard let position = panes.firstIndex(where: { $0.id == pane }) else { return self }
        var updated = self
        updated.panes[position] = transform(panes[position])
        return updated
    }

    public func renamed(_ name: String) -> Workspace {
        var updated = self
        updated.name = name
        return updated
    }

    private func rebuildingTree() -> Workspace {
        var updated = self
        updated.tree = layout.tree(for: panes.map(\.id))
        return updated
    }
}

extension Workspace {
    /// Spec F5, "Agentes que esperan": the agents of the other panes that wait for the user or failed, by harness.
    public func waitingAgents(besides pane: PaneID) -> WaitingAgents {
        let agents = panes.filter { $0.id != pane }.compactMap(\.agent)
        let names = { (kind: AgentStateKind) in
            agents.filter { $0.state.kind == kind }.map(\.harness.rawValue)
        }
        return WaitingAgents(waiting: names(.waiting), failed: names(.failed))
    }
}
