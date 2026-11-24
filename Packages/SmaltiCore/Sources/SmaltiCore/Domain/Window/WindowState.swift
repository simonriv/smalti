/// One window: its workspaces, where it is on screen (nil until the app places it) and whether it is full screen.
public struct WindowState: Equatable, Sendable {
    public let id: WindowID
    public var workspaces: WorkspaceSet
    public var frame: Rect?
    public var isFullScreen: Bool

    public init(id: WindowID, workspaces: WorkspaceSet, frame: Rect?, isFullScreen: Bool) {
        self.id = id
        self.workspaces = workspaces
        self.frame = frame
        self.isFullScreen = isFullScreen
    }

    public func moved(to frame: Rect) -> WindowState {
        var updated = self
        updated.frame = frame
        return updated
    }

    public func fullScreen(_ isOn: Bool) -> WindowState {
        var updated = self
        updated.isFullScreen = isOn
        return updated
    }

    public func with(_ workspaces: WorkspaceSet) -> WindowState {
        var updated = self
        updated.workspaces = workspaces
        return updated
    }

    var allPanes: [Pane] { workspaces.workspaces.flatMap(\.panes) }
}
