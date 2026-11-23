public enum ClosePaneOutcome: Equatable, Sendable {
    case closed
    case alreadyClosed
}

/// Removes a pane from whichever workspace holds it, then releases its terminal. Idempotent.
@MainActor
public struct ClosePane {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ pane: PaneID, in set: inout WorkspaceSet) -> ClosePaneOutcome {
        guard let workspace = set.workspace(containing: pane) else { return .alreadyClosed }
        set = set.updating(workspace) { $0.removing(pane) }
        engine.close(pane)
        return .closed
    }
}
