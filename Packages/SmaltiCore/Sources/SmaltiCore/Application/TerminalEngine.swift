/// Port to whatever runs terminals (libghostty today). Speaks only domain types:
/// no pointers, views or engine-specific values cross it.
@MainActor
public protocol TerminalEngine: AnyObject {
    func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID
    func close(_ pane: PaneID)
    /// The pane's events. The stream has a single consumer: iterate it once per pane.
    func events(for pane: PaneID) -> AsyncStream<TerminalEvent>
}

public enum TerminalEngineError: Error, Equatable, Sendable {
    case engineStartFailed(reason: String)
    case configurationInvalid(diagnostics: [String])
    case surfaceCreationFailed(workingDirectory: String, reason: String)
}
