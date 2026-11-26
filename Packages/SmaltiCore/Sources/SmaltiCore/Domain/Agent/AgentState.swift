import Foundation

/// Which coding-agent CLI runs in a pane. F2 knew only Claude Code; F6 adds Codex, Antigravity and OpenCode.
public struct HarnessID: Hashable, Codable, Sendable, RawRepresentable {
    public static let claude = HarnessID(rawValue: "claude")
    public static let codex = HarnessID(rawValue: "codex")
    public static let antigravity = HarnessID(rawValue: "antigravity")
    public static let opencode = HarnessID(rawValue: "opencode")

    private static let names: [HarnessID: String] = [
        .claude: "Claude Code", .codex: "Codex", .antigravity: "Antigravity", .opencode: "OpenCode",
    ]

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Shown in the interface ("Claude Code"); an unknown id shows as it is.
    public var displayName: String { Self.names[self] ?? rawValue }

    /// One of the harnesses Smalti knows (F6); a shared layout from a newer Smalti may name another.
    public var isKnown: Bool { Self.names[self] != nil }
}

/// Why an agent waits for the user.
public enum WaitReason: Equatable, Sendable {
    /// It finished its turn (or just started) and waits for a prompt.
    case turnFinished
    /// It asks permission to run something, summarised (e.g. `pnpm db:migrate`).
    case permission(String)
    /// It raised a notification with this message.
    case attention(String)
    /// F7.5: Smalti holds a guarded command until the user approves it.
    case approval(ApprovalSubject)
}

/// The state shown for an agent, always with the same colour: working green, waiting amber, failed red,
/// stopped a hollow circle.
public enum AgentState: Equatable, Sendable {
    case working
    case waiting(since: Date, reason: WaitReason)
    case failed(since: Date, message: String)
    case stopped

    /// Working or waiting: the agent is still running.
    var isActive: Bool {
        switch self {
        case .working, .waiting: true
        case .failed, .stopped: false
        }
    }

    /// When it started waiting or failed (for "te espera · 2m" and the attention queue).
    public var since: Date? {
        switch self {
        case .waiting(let since, _), .failed(let since, _): since
        case .working, .stopped: nil
        }
    }

    public var kind: AgentStateKind {
        switch self {
        case .working: .working
        case .waiting: .waiting
        case .failed: .failed
        case .stopped: .stopped
        }
    }
}

/// `AgentState` without its details, as saved in a snapshot.
public enum AgentStateKind: String, Codable, Sendable {
    case working, waiting, failed, stopped

    /// error > te espera > trabajando > detenido; nil without agents.
    public static func mostUrgent(_ kinds: [AgentStateKind]) -> AgentStateKind? {
        [AgentStateKind.failed, .waiting, .working, .stopped].first(where: kinds.contains)
    }
}
