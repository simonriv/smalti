import Foundation

/// A saved workspace: what reopening needs to rebuild it.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let rootDirectory: String
    public let layout: String
    public let tree: SnapshotTree?
    public let focusedIndex: Int?
    public let panes: [PaneSnapshot]

    init(_ workspace: Workspace, scrollbackLines: [PaneID: Int]) {
        let order = workspace.panes.map(\.id)
        name = workspace.name
        rootDirectory = workspace.rootDirectory.path
        layout = workspace.layout.id.rawValue
        tree = workspace.tree.map { SnapshotTree($0, order: order) }
        focusedIndex = workspace.focusedPane.flatMap(order.firstIndex(of:))
        panes = workspace.panes.map { PaneSnapshot($0, scrollbackLines: scrollbackLines[$0.id] ?? 0) }
    }
}

/// Everything saved about a window to reopen it: its workspaces, in order, and which one was active.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let version: Int
    public let savedAt: Date
    public let workspaces: [WorkspaceSnapshot]
    public let activeIndex: Int

    /// `scrollbackLines` holds the lines saved for each pane whose scrollback was kept; the rest count 0.
    public static func capture(_ set: WorkspaceSet, scrollbackLines: [PaneID: Int], at date: Date) -> SessionSnapshot {
        SessionSnapshot(
            version: formatVersion, savedAt: date,
            workspaces: set.workspaces.map { WorkspaceSnapshot($0, scrollbackLines: scrollbackLines) },
            activeIndex: set.workspaces.firstIndex { $0.id == set.activeID } ?? 0)
    }
}
