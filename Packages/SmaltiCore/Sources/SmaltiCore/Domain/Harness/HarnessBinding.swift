import Foundation

/// The harness a pane runs and, once captured, its session (spec F6). Claude's session also lives in the pane's
/// `AgentSession`, fed by its hooks, which wins.
///
/// A binding belongs to one process (`pid`). Without a pid it is pending: a restored pane or one opened from the
/// search typed a resume (or continue) command, and the harness process that comes next consumes it once.
public struct HarnessBinding: Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String?
    public let processStartedAt: Date
    public let pid: Int32?

    public init(harness: HarnessID, sessionID: String?, processStartedAt: Date, pid: Int32? = nil) {
        self.harness = harness
        self.sessionID = sessionID
        self.processStartedAt = processStartedAt
        self.pid = pid
    }

    public var isPending: Bool { pid == nil }
}
