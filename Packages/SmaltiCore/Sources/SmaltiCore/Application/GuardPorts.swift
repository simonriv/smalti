import Foundation

/// What Smalti answers a guarded tool call: let it go through Claude's own permission flow, or refuse it.
public enum GuardDecision: Equatable, Sendable {
    case allow
    case deny(String)
}

/// A tool call the `smalti guard` CLI holds until Smalti answers (spec F7.5). `reply` must be called once.
public struct GuardRequest: Sendable {
    public let id: UUID
    public let pane: PaneID
    public let use: ToolUse
    public let environmentHosts: [String]
    /// What the CLI decided without the user's settings.
    public let localVerdict: GuardVerdict
    public let receivedAt: Date
    public let reply: @Sendable (GuardDecision) -> Void

    public init(
        id: UUID, pane: PaneID, use: ToolUse, environmentHosts: [String], localVerdict: GuardVerdict, receivedAt: Date,
        reply: @escaping @Sendable (GuardDecision) -> Void
    ) {
        self.id = id
        self.pane = pane
        self.use = use
        self.environmentHosts = environmentHosts
        self.localVerdict = localVerdict
        self.receivedAt = receivedAt
        self.reply = reply
    }
}

/// Port (F7.5): the guarded tool calls the panes' agents are waiting on.
@MainActor
public protocol GuardRequests: AnyObject {
    /// One consumer: iterate it once.
    func requests() -> AsyncStream<GuardRequest>
}
