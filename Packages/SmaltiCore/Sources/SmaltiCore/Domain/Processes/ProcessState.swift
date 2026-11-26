/// A process's state as the whole app codes it: green active, hollow idle or stopped, amber not responding to a
/// stop, red zombie.
public enum ProcessState: Equatable, Sendable {
    case active
    case idle
    case stopped
    case unresponsive
    case zombie

    /// At least this much CPU in the last sample counts as active.
    public static let activeThreshold = 0.5

    public static func of(run: RunState, cpu: Double?, phase: StopPhase?) -> ProcessState {
        if run == .zombie { return .zombie }
        switch phase {
        case .unresponsive, .confirming: return .unresponsive
        case .requested, nil: break
        }
        if run == .stopped { return .stopped }
        return (cpu ?? 0) >= activeThreshold ? .active : .idle
    }
}

extension ProcessRecord {
    /// The executable's file name, or the kernel's short name (cut at 16 characters) when the path is unknown.
    public var displayName: String {
        guard let executable, let last = executable.split(separator: "/").last, !last.isEmpty else { return name }
        return String(last)
    }

    /// The command line, or the name when the arguments cannot be read.
    public var command: String {
        arguments.isEmpty ? displayName : arguments.joined(separator: " ")
    }
}
