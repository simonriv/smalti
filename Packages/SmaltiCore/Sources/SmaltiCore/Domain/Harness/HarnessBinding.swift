import Foundation

/// The harness a pane runs and, once captured, its session (spec F6). Claude's session also lives in the pane's
/// `AgentSession`, fed by its hooks, which wins.
public struct HarnessBinding: Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String?
    public let processStartedAt: Date

    public init(harness: HarnessID, sessionID: String?, processStartedAt: Date) {
        self.harness = harness
        self.sessionID = sessionID
        self.processStartedAt = processStartedAt
    }
}
