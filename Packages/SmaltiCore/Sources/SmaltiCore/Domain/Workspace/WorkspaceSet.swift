public enum WorkspaceSetError: Error, Equatable, Sendable {
    case cannotCloseLastWorkspace
}

/// The ordered workspaces of a window and which one is active.
///
/// Invariant: there is at least one workspace and `activeID` is one of them.
public struct WorkspaceSet: Sendable, Equatable {
    /// Panes beyond this position get no `⌘n` index.
    private static let maxPaneIndex = 9

    public private(set) var workspaces: [Workspace]
    public private(set) var activeID: WorkspaceID

    public init(first: Workspace) {
        workspaces = [first]
        activeID = first.id
    }

    public var active: Workspace {
        // Safe fallback: the invariant guarantees the active workspace exists.
        workspaces.first { $0.id == activeID } ?? workspaces[0]
    }

    public func adding(_ workspace: Workspace) -> WorkspaceSet {
        guard !workspaces.contains(where: { $0.id == workspace.id }) else { return self }
        var updated = self
        updated.workspaces.append(workspace)
        updated.activeID = workspace.id
        return updated
    }

    public func activating(_ id: WorkspaceID) -> WorkspaceSet {
        guard workspaces.contains(where: { $0.id == id }) else { return self }
        var updated = self
        updated.activeID = id
        return updated
    }

    /// Activates the workspace at `index`, counting from 1; out of range does nothing.
    public func activating(index: Int) -> WorkspaceSet {
        guard workspaces.indices.contains(index - 1) else { return self }
        return activating(workspaces[index - 1].id)
    }

    public func removing(_ id: WorkspaceID) throws(WorkspaceSetError) -> WorkspaceSet {
        guard workspaces.count > 1 else { throw .cannotCloseLastWorkspace }
        guard let position = workspaces.firstIndex(where: { $0.id == id }) else { return self }
        var updated = self
        updated.workspaces.remove(at: position)
        if activeID == id {
            updated.activeID = updated.workspaces[max(position - 1, 0)].id
        }
        return updated
    }

    public func updating(_ id: WorkspaceID, _ transform: (Workspace) -> Workspace) -> WorkspaceSet {
        guard let position = workspaces.firstIndex(where: { $0.id == id }) else { return self }
        var updated = self
        updated.workspaces[position] = transform(workspaces[position])
        return updated
    }

    public func workspace(containing pane: PaneID) -> WorkspaceID? {
        workspaces.first { $0.contains(pane) }?.id
    }

    /// Position of `pane` in the active workspace, 1…9; `nil` elsewhere or above 9.
    public func paneIndex(of pane: PaneID) -> Int? {
        active.index(of: pane).flatMap { $0 <= Self.maxPaneIndex ? $0 : nil }
    }
}
