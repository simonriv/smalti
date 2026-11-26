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
    /// The CLI cut the command to send it: it cannot be judged again, so it always asks.
    public let isTruncated: Bool
    public let reply: @Sendable (GuardDecision) -> Void

    public init(
        id: UUID, pane: PaneID, use: ToolUse, environmentHosts: [String], localVerdict: GuardVerdict, receivedAt: Date,
        isTruncated: Bool = false, reply: @escaping @Sendable (GuardDecision) -> Void
    ) {
        self.isTruncated = isTruncated
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
    /// The ids of requests whose hook went away before an answer (final review: Claude cancelled the tool).
    func cancellations() -> AsyncStream<UUID>
}

public enum ProjectPermissionsError: Error, Equatable, Sendable {
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)
    /// F7.5: the project is the user's home, whose settings are global.
    case homeFolder(path: String)
    /// The settings file is not a JSON object, or its `permissions.deny` is not a list of texts.
    case notAnObject(path: String)
    case denyNotAList(path: String)
    case invalidJSON(path: String)

    public func message(_ texts: GuardTexts) -> String {
        switch self {
        case .unreadable(let path, let reason): texts.unreadableFile(["path": path, "reason": reason])
        case .unwritable(let path, let reason): texts.unwritableFile(["path": path, "reason": reason])
        case .homeFolder(let path): texts.unwritableFile(["path": path, "reason": texts.homeFolder])
        case .notAnObject(let path): texts.unreadableFile(["path": path, "reason": texts.notAnObject])
        case .denyNotAList(let path): texts.unreadableFile(["path": path, "reason": texts.denyNotAList])
        case .invalidJSON(let path): texts.unreadableFile(["path": path, "reason": texts.invalidJSON])
        }
    }
}

/// Port (F7.5): the `permissions.deny` rules of a project's local Claude Code settings.
public protocol ProjectPermissions: Sendable {
    func deniedRules(in project: String) throws(ProjectPermissionsError) -> [String]
    func setDeniedRules(_ rules: [String], in project: String) throws(ProjectPermissionsError)
}
