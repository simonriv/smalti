/// Opens a new terminal pane and returns its initial domain state.
@MainActor
public struct OpenPane {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> Pane {
        let id = try engine.open(spec)
        return Pane(id: id, workingDirectory: spec.workingDirectory)
    }
}
