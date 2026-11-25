import Foundation

/// Saves the active workspace as a layout with a name, without scrollback.
@MainActor
public struct SaveNamedLayout {
    private let layouts: any NamedLayouts

    public init(layouts: any NamedLayouts) {
        self.layouts = layouts
    }

    public func execute(_ workspace: Workspace, as name: LayoutName) throws(SessionArchiveError) {
        try layouts.save(WorkspaceSnapshot(workspace, scrollbackLines: [:]), as: name)
    }
}

public struct NamedLayoutOutcome: Equatable, Sendable {
    /// Agent sessions not resumed because they already run in another pane.
    public let skippedLiveSessions: [String]
    public let failures: [String]
}

/// Opens a saved layout as a new workspace named after it: its programs start again and its agents resume,
/// except a session that already runs in another pane (two processes on one session would clash).
@MainActor
public struct RestoreNamedLayout {
    private let layouts: any NamedLayouts
    private let restore: RestoreSession

    public init(layouts: any NamedLayouts, restore: RestoreSession) {
        self.layouts = layouts
        self.restore = restore
    }

    public func execute(_ name: LayoutName, into set: inout WorkspaceSet, home: WorkingDirectory)
        throws(SessionArchiveError) -> NamedLayoutOutcome
    {
        let saved = try layouts.layout(named: name)
        let live = Set(set.workspaces.flatMap(\.panes).compactMap(\.agent?.sessionID))
        let planned = plan(saved, named: name, skipping: live)
        let built = restore.restore(planned.workspace, savedAt: Date.distantPast, home: home)
        guard let workspace = built.workspace else {
            return NamedLayoutOutcome(skippedLiveSessions: planned.skipped, failures: built.failures)
        }
        set.active.panes.forEach { restore.hide($0.id) }
        set = set.adding(workspace)
        return NamedLayoutOutcome(skippedLiveSessions: planned.skipped, failures: built.failures)
    }

    private func plan(_ saved: WorkspaceSnapshot, named name: LayoutName, skipping live: Set<String>)
        -> (workspace: PlannedWorkspace, skipped: [String])
    {
        var skipped: [String] = []
        let panes = saved.panes.map { pane in
            var launch = PaneLaunch.saved(pane)
            if let id = pane.agent?.sessionID, live.contains(id) {
                skipped.append(id)
                launch = .shell
            }
            // A layout is a template: fresh identities, no saved output or history.
            return PlannedPane(
                id: UUID(), workingDirectory: pane.workingDirectory, restoresScrollback: false,
                restoresHistory: false, launch: launch)
        }
        let workspace = PlannedWorkspace(
            name: name.rawValue, rootDirectory: saved.rootDirectory, layout: LayoutID(rawValue: saved.layout),
            tree: saved.tree, focusedIndex: saved.focusedIndex, panes: panes)
        return (workspace, skipped)
    }
}
