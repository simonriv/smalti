import Foundation

/// Which coding-agent CLI runs in a pane. F2 knows only Claude Code; F6 adds the others as new values.
public struct HarnessID: Hashable, Codable, Sendable, RawRepresentable {
    public static let claude = HarnessID(rawValue: "claude")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Why an agent waits for the user.
public enum WaitReason: Equatable, Sendable {
    /// It finished its turn (or just started) and waits for a prompt.
    case turnFinished
    /// It asks permission to run something, summarised (e.g. `pnpm db:migrate`).
    case permission(String)
    /// It raised a notification with this message.
    case attention(String)
}

/// The state shown for an agent, always with the same colour: working green, waiting amber, failed red,
/// stopped a hollow circle.
public enum AgentState: Equatable, Sendable {
    case working
    case waiting(since: Date, reason: WaitReason)
    case failed(since: Date, message: String)
    case stopped

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
}
