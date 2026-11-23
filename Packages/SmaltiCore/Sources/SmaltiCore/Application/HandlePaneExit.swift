public struct PaneExit: Sendable {
    public let pane: PaneID
    public let exitCode: Int?
    public let lifetime: Duration

    public init(pane: PaneID, exitCode: Int?, lifetime: Duration) {
        self.pane = pane
        self.exitCode = exitCode
        self.lifetime = lifetime
    }
}

/// What happened when a pane's process exited: the pane closes, and a shell that died right after starting
/// is reported instead of letting the window vanish without a word.
public enum PaneExitOutcome: Equatable, Sendable {
    case closed
    case closedAfterFailedStart(exitCode: Int?)
    case alreadyClosed
}

@MainActor
public struct HandlePaneExit {
    /// Below this lifetime an exit means the shell or command failed to start (Ghostty uses the same bound).
    public static let minimumHealthyLifetime: Duration = .milliseconds(250)

    private let closePane: ClosePane

    public init(engine: any TerminalEngine) {
        closePane = ClosePane(engine: engine)
    }

    public func execute(_ exit: PaneExit, in set: inout WorkspaceSet) -> PaneExitOutcome {
        switch closePane.execute(exit.pane, in: &set) {
        case .alreadyClosed: .alreadyClosed
        case .closed:
            exit.lifetime < Self.minimumHealthyLifetime ? .closedAfterFailedStart(exitCode: exit.exitCode) : .closed
        }
    }
}
