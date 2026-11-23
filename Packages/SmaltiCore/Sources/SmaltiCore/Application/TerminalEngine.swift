/// Port to whatever runs terminals (libghostty today). Speaks only domain types:
/// no pointers, views or engine-specific values cross it.
///
/// `close` releases the pane without emitting events and finishes its stream. `.closeRequested` and `.exited`
/// are requests the app routes to `ClosePane`; the engine may raise them from inside its own call stack, so
/// the adapter defers them to the next run loop cycle.
@MainActor
public protocol TerminalEngine: AnyObject {
    /// Opens a terminal for `pane`. The caller chooses the id so a restored pane keeps its identity.
    func open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError)
    func close(_ pane: PaneID)
    /// Makes the pane's terminal visible again.
    func show(_ pane: PaneID)
    /// Hides the pane's terminal, for example when its workspace is not active.
    func hide(_ pane: PaneID)
    /// The pane's events. The stream has a single consumer: iterate it once per pane.
    func events(for pane: PaneID) -> AsyncStream<TerminalEvent>
}

public enum TerminalEngineError: Error, Equatable, Sendable {
    case engineStartFailed(reason: String)
    case configurationInvalid(diagnostics: [String])
    case surfaceCreationFailed(workingDirectory: String, reason: String)
}
