public enum WorkspaceSetError: Error, Equatable, Sendable {
    case cannotCloseLastWorkspace
}

/// The ordered workspaces of a window and which one is active.
///
/// Invariant: there is at least one workspace and `activeID` is one of them.
public struct WorkspaceSet: Sendable, Equatable {
    public private(set) var workspaces: [Workspace]
    public private(set) var activeID: WorkspaceID

    public init(first: Workspace) {
        workspaces = [first]
        activeID = first.id
    }

    public var active: Workspace {
        // Every mutation keeps `activeID` pointing at an existing workspace, so a miss is a bug here.
        guard let found = workspaces.first(where: { $0.id == activeID }) else {
            preconditionFailure("WorkspaceSet invariant broken: active workspace \(activeID) is missing")
        }
        return found
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
        guard let position = workspaces.firstIndex(where: { $0.id == id }) else { return self }
        guard workspaces.count > 1 else { throw .cannotCloseLastWorkspace }
        var updated = self
        updated.workspaces.remove(at: position)
        if activeID == id {
            updated.activeID = updated.workspaces[max(position - 1, 0)].id
        }
        return updated
    }

    public func updating(_ id: WorkspaceID, _ transform: (Workspace) -> Workspace) -> WorkspaceSet {
        guard let position = workspaces.firstIndex(where: { $0.id == id }) else { return self }
        let transformed = transform(workspaces[position])
        // A transform that renames identity would break unique ids and `activeID`.
        guard transformed.id == id else { return self }
        var updated = self
        updated.workspaces[position] = transformed
        return updated
    }

    /// What a user changes on purpose (workspaces, panes, layouts), without titles, directories or agent states.
    public var structure: [[String]] {
        workspaces.map { [$0.id.description, $0.layout.id.rawValue] + $0.panes.map(\.id.description) }
    }

    public func workspace(containing pane: PaneID) -> WorkspaceID? {
        workspaces.first { $0.contains(pane) }?.id
    }

    /// Position of `pane` in the active workspace while it has a `⌘n` shortcut; `nil` elsewhere or beyond it.
    public func paneIndex(of pane: PaneID) -> Int? {
        active.index(of: pane).flatMap { NumberedShortcuts.range.contains($0) ? $0 : nil }
    }
}
