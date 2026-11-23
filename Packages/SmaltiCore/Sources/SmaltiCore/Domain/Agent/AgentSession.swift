import Foundation

/// A coding-agent session running in a pane, as its hooks report it.
public struct AgentSession: Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String
    public private(set) var title: String?
    public private(set) var state: AgentState
    public let startedAt: Date

    public init(harness: HarnessID, sessionID: String, title: String?, state: AgentState, startedAt: Date) {
        self.harness = harness
        self.sessionID = sessionID
        self.title = title
        self.state = state
        self.startedAt = startedAt
    }

    public var snapshot: AgentSnapshot {
        AgentSnapshot(harness: harness, sessionID: sessionID, title: title, lastState: state.kind)
    }
}
