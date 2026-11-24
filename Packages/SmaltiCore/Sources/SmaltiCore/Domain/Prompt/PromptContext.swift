import Foundation

/// What the prompt can show for one shell at one moment (spec F5, module table). Local facts come from zsh; git,
/// runtime, agents and the kube context come from Smalti.
public struct PromptContext: Equatable, Sendable {
    public var directory: String
    public var home: String
    public var repoRoot: String?
    public var branch: String?
    public var changes: GitChanges?
    public var runtime: RuntimeVersion?
    public var lastExit: Int
    public var duration: Duration?
    public var now: Date
    public var timeZone: TimeZone
    public var agents: WaitingAgents
    public var awsProfile: String?
    public var kubeContext: String?

    public init(directory: String, home: String) {
        self.directory = directory
        self.home = home
        lastExit = 0
        now = Date(timeIntervalSince1970: 0)
        timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        agents = WaitingAgents()
    }
}

public struct GitChanges: Equatable, Sendable {
    /// Changed in the working tree, not staged.
    public let modified: Int
    public let staged: Int

    public init(modified: Int, staged: Int) {
        self.modified = modified
        self.staged = staged
    }
}

public enum RuntimeKind: String, CaseIterable, Sendable {
    case node, bun, python, go
}

public struct RuntimeVersion: Equatable, Sendable {
    public let kind: RuntimeKind
    /// As shown: "22.11".
    public let version: String

    public init(kind: RuntimeKind, version: String) {
        self.kind = kind
        self.version = version
    }
}

/// Agents of the same workspace that wait for the user or failed, by name ("claude").
public struct WaitingAgents: Equatable, Sendable {
    public let waiting: [String]
    public let failed: [String]

    public init(waiting: [String] = [], failed: [String] = []) {
        self.waiting = waiting
        self.failed = failed
    }
}
