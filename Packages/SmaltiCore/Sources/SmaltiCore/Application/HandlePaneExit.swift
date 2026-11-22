/// What happens when a pane's process exits: the pane closes, unless the shell died right after starting,
/// which is reported instead of letting the window vanish without a word.
public enum PaneExitOutcome: Equatable, Sendable {
    case closePane
    case reportFailedStart(exitCode: Int?)
}

public struct HandlePaneExit: Sendable {
    /// Below this lifetime an exit means the shell or command failed to start (Ghostty uses the same bound).
    public static let minimumHealthyLifetime: Duration = .milliseconds(250)

    public init() {}

    public func execute(exitCode: Int?, lifetime: Duration) -> PaneExitOutcome {
        lifetime < Self.minimumHealthyLifetime ? .reportFailedStart(exitCode: exitCode) : .closePane
    }
}
