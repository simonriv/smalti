/// Port: what Smalti needs from a coding-agent CLI. F2 resumes Claude Code; F6 adds detection and listing.
public protocol HarnessAdapter: Sendable {
    var harness: HarnessID { get }
    /// Shown in the interface ("Claude Code").
    var displayName: String { get }
    /// The shell command that resumes `agent` (e.g. `claude --resume 7f3a`).
    func resumeCommand(for agent: AgentSnapshot) -> String
}

/// The known harness adapters, looked up by id (no switch per harness). For a repeated id the first one wins.
public struct HarnessRegistry: Sendable {
    private let adapters: [HarnessID: any HarnessAdapter]

    public init(_ adapters: [any HarnessAdapter]) {
        self.adapters = Dictionary(adapters.map { ($0.harness, $0) }) { first, _ in first }
    }

    public func adapter(for harness: HarnessID) -> (any HarnessAdapter)? { adapters[harness] }
}
