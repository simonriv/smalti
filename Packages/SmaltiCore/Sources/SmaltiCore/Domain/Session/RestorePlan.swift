import Foundation

/// Restore everything a pane had, or only the layouts with clean shells.
public enum RestoreMode: Sendable {
    case full, layoutsOnly
}

/// What a restored pane runs once its shell starts.
public enum PaneLaunch: Equatable, Sendable {
    case shell
    case resume(AgentSnapshot)
    case relaunch(RelaunchCommand)
}

public struct PlannedPane: Equatable, Sendable {
    public let id: UUID
    public let workingDirectory: String
    /// Only panes that were at their shell: an agent or a full-screen program repaints its own screen.
    public let restoresScrollback: Bool
    public let restoresHistory: Bool
    public let launch: PaneLaunch

    public init(id: UUID, workingDirectory: String, restoresScrollback: Bool, restoresHistory: Bool, launch: PaneLaunch)
    {
        self.id = id
        self.workingDirectory = workingDirectory
        self.restoresScrollback = restoresScrollback
        self.restoresHistory = restoresHistory
        self.launch = launch
    }
}

public struct PlannedWorkspace: Equatable, Sendable {
    public let name: String
    public let rootDirectory: String
    public let layout: LayoutID
    /// The saved split tree, or `nil` to rebuild it with the layout (some panes were left out).
    public let tree: SnapshotTree?
    public let focusedIndex: Int?
    public let panes: [PlannedPane]

    public init(
        name: String, rootDirectory: String, layout: LayoutID, tree: SnapshotTree?, focusedIndex: Int?,
        panes: [PlannedPane]
    ) {
        self.name = name
        self.rootDirectory = rootDirectory
        self.layout = layout
        self.tree = tree
        self.focusedIndex = focusedIndex
        self.panes = panes
    }
}

/// What reopening will rebuild, decided from a snapshot, a mode and the user's selection. Pure.
public struct RestorePlan: Equatable, Sendable {
    public let workspaces: [PlannedWorkspace]
    public let activeIndex: Int

    public init(workspaces: [PlannedWorkspace], activeIndex: Int) {
        self.workspaces = workspaces
        self.activeIndex = activeIndex
    }

    /// The plan of one saved window.
    public static func make(from window: WindowSnapshot, mode: RestoreMode, selection: RestoreSelection)
        -> RestorePlan
    {
        let planned = window.workspaces.enumerated().compactMap { index, workspace in
            plan(workspace, mode: mode, selection: selection).map { (savedIndex: index, workspace: $0) }
        }
        let active = planned.firstIndex { $0.savedIndex == window.activeIndex } ?? 0
        return RestorePlan(workspaces: planned.map(\.workspace), activeIndex: active)
    }

    /// The plan of the window that was in front; an empty plan for a session without windows.
    public static func make(from snapshot: SessionSnapshot, mode: RestoreMode, selection: RestoreSelection)
        -> RestorePlan
    {
        guard let front = snapshot.front else { return RestorePlan(workspaces: [], activeIndex: 0) }
        return make(from: front, mode: mode, selection: selection)
    }

    private static func plan(_ workspace: WorkspaceSnapshot, mode: RestoreMode, selection: RestoreSelection)
        -> PlannedWorkspace?
    {
        let kept = workspace.panes.enumerated().filter { selection.isChecked($0.element.id) }
        guard !kept.isEmpty else { return nil }
        let isComplete = kept.count == workspace.panes.count
        return PlannedWorkspace(
            name: workspace.name, rootDirectory: workspace.rootDirectory, layout: LayoutID(rawValue: workspace.layout),
            tree: isComplete ? workspace.tree : nil,
            focusedIndex: kept.firstIndex { $0.offset == workspace.focusedIndex } ?? 0,
            panes: kept.map { plan($0.element, mode: mode) })
    }

    private static func plan(_ pane: PaneSnapshot, mode: RestoreMode) -> PlannedPane {
        guard mode == .full else {
            return PlannedPane(
                id: pane.id, workingDirectory: pane.workingDirectory, restoresScrollback: false,
                restoresHistory: false, launch: .shell)
        }
        let launch: PaneLaunch = pane.agent.map(PaneLaunch.resume) ?? pane.relaunch.map(PaneLaunch.relaunch) ?? .shell
        return PlannedPane(
            id: pane.id, workingDirectory: pane.workingDirectory,
            restoresScrollback: launch == .shell && pane.scrollbackLines > 0,
            restoresHistory: true, launch: launch)
    }
}
