import Foundation

public struct CreateWorkspaceRequest: Sendable {
    public let pane: OpenPaneRequest
    public let layout: any LayoutStrategy

    public init(pane: OpenPaneRequest, layout: any LayoutStrategy) {
        self.pane = pane
        self.layout = layout
    }
}

/// Adds a workspace rooted at the focused pane's directory, activates it and opens its first pane.
@MainActor
public struct CreateWorkspace {
    private let engine: any TerminalEngine
    private let openPane: OpenPane

    public init(engine: any TerminalEngine, environment: PaneEnvironment) {
        self.engine = engine
        openPane = OpenPane(engine: engine, environment: environment)
    }

    public init(engine: any TerminalEngine, version: String, environment: [String: String] = [:]) {
        self.init(engine: engine, environment: PaneEnvironment(version: version, extra: environment))
    }

    public func execute(_ request: CreateWorkspaceRequest, in set: inout WorkspaceSet) throws(OpenPaneError)
        -> WorkspaceID
    {
        let outgoing = set.active.panes.map(\.id)
        let root = set.active.directoryForNewPane
        let workspace = Workspace.empty(name: root.lastComponent, rootDirectory: root, layout: request.layout)
        // Work on a copy so a failed open leaves `set` untouched.
        var candidate = set.adding(workspace)
        _ = try openPane.execute(request.pane, in: &candidate)
        outgoing.forEach(engine.hide)
        set = candidate
        return workspace.id
    }
}

/// Renames the active workspace; a blank name changes nothing.
@MainActor
public struct RenameWorkspace {
    public init() {}

    public func execute(_ name: String, in set: inout WorkspaceSet) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        set = set.updating(set.activeID) { $0.renamed(trimmed) }
    }
}

public enum WorkspaceTarget: Equatable, Sendable {
    case id(WorkspaceID)
    /// Position in the set, counting from 1.
    case index(Int)
}

/// Makes another workspace active: hides the outgoing panes and shows the incoming ones.
@MainActor
public struct SwitchWorkspace {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ target: WorkspaceTarget, in set: inout WorkspaceSet) {
        let outgoing = set.active
        let updated = activate(target, in: set)
        guard updated.activeID != outgoing.id else { return }
        outgoing.panes.forEach { engine.hide($0.id) }
        updated.active.panes.forEach { engine.show($0.id) }
        set = updated
    }

    private func activate(_ target: WorkspaceTarget, in set: WorkspaceSet) -> WorkspaceSet {
        switch target {
        case .id(let id): set.activating(id)
        case .index(let position): set.activating(index: position)
        }
    }
}

/// Closes a workspace and all its terminals; the last workspace cannot be closed.
@MainActor
public struct CloseWorkspace {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    /// Returns the panes it closed, so callers can forget what they kept about them; none for an unknown id.
    @discardableResult
    public func execute(_ id: WorkspaceID, in set: inout WorkspaceSet) throws(WorkspaceSetError) -> [PaneID] {
        let closing = set.workspaces.first { $0.id == id }?.panes.map(\.id) ?? []
        let updated = try set.removing(id)
        closing.forEach(engine.close)
        if id == set.activeID {
            updated.active.panes.forEach { engine.show($0.id) }
        }
        set = updated
        return closing
    }
}
