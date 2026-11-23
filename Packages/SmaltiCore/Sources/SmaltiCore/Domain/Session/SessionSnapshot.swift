import Foundation

/// A saved workspace: what reopening needs to rebuild it.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let rootDirectory: String
    public let layout: String
    public let tree: SnapshotTree?
    public let focusedIndex: Int?
    public let panes: [PaneSnapshot]

    public init(
        name: String, rootDirectory: String, layout: String, tree: SnapshotTree?, focusedIndex: Int?,
        panes: [PaneSnapshot]
    ) {
        self.name = name
        self.rootDirectory = rootDirectory
        self.layout = layout
        self.tree = tree
        self.focusedIndex = focusedIndex
        self.panes = panes
    }

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

/// Everything saved about the app to reopen it (format 2, F4.5): its windows, in order, and which one was in front.
/// Format 1 (F2–F4) had a single window's workspaces at the top level; it still decodes, as one window.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 2

    public let version: Int
    public let savedAt: Date
    public let windows: [WindowSnapshot]
    public let frontIndex: Int

    public init(version: Int, savedAt: Date, windows: [WindowSnapshot], frontIndex: Int) {
        self.version = version
        self.savedAt = savedAt
        self.windows = windows
        self.frontIndex = frontIndex
    }

    /// One window without a frame: how format 1 reads, and what single-window callers build.
    public init(version: Int, savedAt: Date, workspaces: [WorkspaceSnapshot], activeIndex: Int) {
        self.init(
            version: version, savedAt: savedAt,
            windows: [
                WindowSnapshot(frame: nil, isFullScreen: false, workspaces: workspaces, activeIndex: activeIndex)
            ],
            frontIndex: 0)
    }

    /// Every saved workspace, window after window.
    public var workspaces: [WorkspaceSnapshot] { windows.flatMap(\.workspaces) }


    /// `scrollbackLines` holds the lines saved for each pane whose scrollback was kept; the rest count 0.
    public static func capture(_ set: WindowSet, scrollbackLines: [PaneID: Int], at date: Date) -> SessionSnapshot {
        SessionSnapshot(
            version: formatVersion, savedAt: date,
            windows: set.windows.map { WindowSnapshot($0, scrollbackLines: scrollbackLines) },
            frontIndex: set.windows.firstIndex { $0.id == set.frontID } ?? 0)
    }

    /// A single window's workspaces, without a frame.
    public static func capture(_ set: WorkspaceSet, scrollbackLines: [PaneID: Int], at date: Date) -> SessionSnapshot {
        let window = WindowState(id: WindowID(), workspaces: set, frame: nil, isFullScreen: false)
        return capture(WindowSet(first: window), scrollbackLines: scrollbackLines, at: date)
    }

    private enum CodingKeys: String, CodingKey {
        case version, savedAt, windows, frontIndex
        case workspaces, activeIndex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let savedAt = try container.decode(Date.self, forKey: .savedAt)
        guard version >= 2 else {
            self.init(
                version: version, savedAt: savedAt,
                workspaces: try container.decode([WorkspaceSnapshot].self, forKey: .workspaces),
                activeIndex: try container.decode(Int.self, forKey: .activeIndex))
            return
        }
        self.init(
            version: version, savedAt: savedAt,
            windows: try container.decode([WindowSnapshot].self, forKey: .windows),
            frontIndex: try container.decode(Int.self, forKey: .frontIndex))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always the current format: the body is format 2 even for a session read from format 1.
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(windows, forKey: .windows)
        try container.encode(frontIndex, forKey: .frontIndex)
    }
}
