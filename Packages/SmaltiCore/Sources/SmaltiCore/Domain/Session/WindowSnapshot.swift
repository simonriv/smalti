/// A saved window: where it was, whether it was full screen, its workspaces in order and which one was active.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public let frame: Rect?
    public let isFullScreen: Bool
    public let workspaces: [WorkspaceSnapshot]
    public let activeIndex: Int

    public init(frame: Rect?, isFullScreen: Bool, workspaces: [WorkspaceSnapshot], activeIndex: Int) {
        self.frame = frame
        self.isFullScreen = isFullScreen
        self.workspaces = workspaces
        self.activeIndex = activeIndex
    }

    init(_ window: WindowState, scrollbackLines: [PaneID: Int], editors: [PaneID: EditorPosition]) {
        let set = window.workspaces
        frame = window.frame
        isFullScreen = window.isFullScreen
        workspaces = set.workspaces.map { WorkspaceSnapshot($0, scrollbackLines: scrollbackLines, editors: editors) }
        activeIndex = set.workspaces.firstIndex { $0.id == set.activeID } ?? 0
    }
}
