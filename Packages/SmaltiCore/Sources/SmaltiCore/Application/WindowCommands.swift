/// Opens a window with one workspace rooted at `directory` and its first pane, and puts it in front. With no
/// windows yet (`set` is nil), it becomes the first one.
@MainActor
public struct OpenWindow {
    private let openPane: OpenPane

    public init(engine: any TerminalEngine, environment: PaneEnvironment) {
        openPane = OpenPane(engine: engine, environment: environment)
    }

    public init(engine: any TerminalEngine, version: String, environment: [String: String] = [:]) {
        self.init(engine: engine, environment: PaneEnvironment(version: version, extra: environment))
    }

    public func execute(_ request: CreateWorkspaceRequest, in directory: WorkingDirectory, into set: inout WindowSet?)
        throws(OpenPaneError) -> WindowID
    {
        let workspace = Workspace.empty(name: directory.lastComponent, rootDirectory: directory, layout: request.layout)
        var workspaces = WorkspaceSet(first: workspace)
        _ = try openPane.execute(request.pane, in: &workspaces)
        let window = WindowState(id: WindowID(), workspaces: workspaces, frame: nil, isFullScreen: false)
        set = set.map { $0.opening(window) } ?? WindowSet(first: window)
        return window.id
    }

    /// Same, for callers that always have a window already.
    public func execute(_ request: CreateWorkspaceRequest, in directory: WorkingDirectory, into set: inout WindowSet)
        throws(OpenPaneError) -> WindowID
    {
        var optional: WindowSet? = set
        let id = try execute(request, in: directory, into: &optional)
        if let optional { set = optional }
        return id
    }
}

public enum CloseWindowOutcome: Equatable, Sendable {
    case closed
    /// The only window: closing it quits the app (⌘Q), so nothing was closed here.
    case isLast
}

/// Closes a window and every pane in it. The last window is left to the app, which quits and saves it.
@MainActor
public struct CloseWindow {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ id: WindowID, in set: inout WindowSet) -> CloseWindowOutcome {
        guard let window = set.windows.first(where: { $0.id == id }) else { return .closed }
        do {
            set = try set.closing(id)
        } catch {
            return .isLast
        }
        window.allPanes.forEach { engine.close($0.id) }
        return .closed
    }
}
