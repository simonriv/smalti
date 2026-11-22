public struct OpenPaneRequest: Sendable {
    public let shell: TerminalCommand
    public let geometry: LayoutGeometry

    public init(shell: TerminalCommand, geometry: LayoutGeometry) {
        self.shell = shell
        self.geometry = geometry
    }
}

public enum OpenPaneError: Error, Equatable, Sendable {
    case paneTooSmall(minimum: Size)
    case engine(TerminalEngineError)
}

/// Opens a terminal in the active workspace, unless the layout would shrink a pane below the minimum.
@MainActor
public struct OpenPane {
    private let engine: any TerminalEngine
    private let environment: [String: String]

    public init(engine: any TerminalEngine, environment: [String: String]) {
        self.engine = engine
        self.environment = environment
    }

    public func execute(_ request: OpenPaneRequest, in set: inout WorkspaceSet) throws(OpenPaneError) -> PaneID {
        let directory = set.active.directoryForNewPane
        try ensureFits(request.geometry, adding: directory, to: set.active)
        let spec = TerminalSessionSpec(
            workingDirectory: directory, command: request.shell, environment: environment)
        let id: PaneID
        do {
            id = try engine.open(spec)
        } catch {
            throw .engine(error)
        }
        let pane = Pane(id: id, workingDirectory: directory)
        set = set.updating(set.activeID) { $0.adding(pane) }
        return id
    }

    /// Checks with a provisional id, so the engine is never asked to open a pane that cannot fit.
    private func ensureFits(
        _ geometry: LayoutGeometry, adding directory: WorkingDirectory, to workspace: Workspace
    ) throws(OpenPaneError) {
        let candidate = workspace.adding(Pane(id: PaneID(), workingDirectory: directory))
        guard let tree = candidate.tree, geometry.fits(tree) else {
            throw .paneTooSmall(minimum: geometry.minimumPaneSize)
        }
    }
}
