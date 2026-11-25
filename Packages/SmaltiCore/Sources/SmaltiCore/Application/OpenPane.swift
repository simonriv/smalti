public struct OpenPaneRequest: Sendable {
    public let shell: TerminalCommand
    public let geometry: LayoutGeometry
    /// Last resort when the current directory and the workspace root are gone.
    public let home: WorkingDirectory?
    /// F6: where to open instead of the focused pane's directory, what to type once the shell starts, and the
    /// harness binding the pane begins with (a session opened from the search).
    public let directory: WorkingDirectory?
    public let initialInput: String?
    public let binding: HarnessBinding?

    public init(
        shell: TerminalCommand, geometry: LayoutGeometry, home: WorkingDirectory? = nil,
        directory: WorkingDirectory? = nil, initialInput: String? = nil, binding: HarnessBinding? = nil
    ) {
        self.shell = shell
        self.geometry = geometry
        self.home = home
        self.directory = directory
        self.initialInput = initialInput
        self.binding = binding
    }
}

public enum OpenPaneError: Error, Equatable, Sendable {
    case paneTooSmall(minimum: Size)
    case engine(TerminalEngineError)
}

/// Opens a terminal in the active workspace, unless the layout would shrink a pane below the minimum.
///
/// R1 is enforced here, not by the caller: every pane's environment carries `ChildEnvironment.smalti`, which
/// wins over any extra variable with the same name.
@MainActor
public struct OpenPane {
    private let engine: any TerminalEngine
    private let environment: PaneEnvironment

    public init(engine: any TerminalEngine, environment: PaneEnvironment) {
        self.engine = engine
        self.environment = environment
    }

    public init(engine: any TerminalEngine, version: String, environment: [String: String] = [:]) {
        self.init(engine: engine, environment: PaneEnvironment(version: version, extra: environment))
    }

    public func execute(_ request: OpenPaneRequest, in set: inout WorkspaceSet) throws(OpenPaneError) -> PaneID {
        let directory = request.directory ?? set.active.directoryForNewPane
        try ensureFits(request.geometry, adding: directory, to: set.active)
        let id = PaneID()
        let opened = try open(
            id, request, candidates: [directory, set.active.rootDirectory] + [request.home].compactMap { $0 })
        let pane = Pane(id: id, workingDirectory: opened)
        set = set.updating(set.activeID) { $0.adding(request.binding.map(pane.binding) ?? pane) }
        return id
    }

    /// Opens in the first directory that still exists (the focused pane's may have been deleted).
    private func open(_ id: PaneID, _ request: OpenPaneRequest, candidates: [WorkingDirectory])
        throws(OpenPaneError) -> WorkingDirectory
    {
        var lastError = TerminalEngineError.surfaceCreationFailed(workingDirectory: "", reason: "no directory")
        var tried: Set<WorkingDirectory> = []
        for directory in candidates where tried.insert(directory).inserted {
            let spec = TerminalSessionSpec(
                workingDirectory: directory, command: request.shell, environment: environment.variables(for: id),
                initialInput: request.initialInput)
            do {
                try engine.open(spec, as: id)
                return directory
            } catch {
                lastError = error
                guard case .surfaceCreationFailed = error else { break }
            }
        }
        throw .engine(lastError)
    }

    /// Checks with a provisional id, so the engine is never asked to open a pane that cannot fit.
    private func ensureFits(
        _ geometry: LayoutGeometry, adding directory: WorkingDirectory, to workspace: Workspace
    ) throws(OpenPaneError) {
        let candidate = workspace.adding(Pane(id: PaneID(), workingDirectory: directory))
        guard let tree = candidate.tree else {
            // `adding` always rebuilds the tree from at least one pane.
            preconditionFailure("Workspace has no layout tree after adding a pane")
        }
        guard geometry.fits(tree) else { throw .paneTooSmall(minimum: geometry.minimumPaneSize) }
    }
}
