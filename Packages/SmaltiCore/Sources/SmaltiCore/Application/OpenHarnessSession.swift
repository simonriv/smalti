import Foundation

/// What opening a saved session does (spec F6): a new pane, in the session's directory (the home when it is gone,
/// with a notice), running the harness's resume or fork command.
public enum OpenPlan: Equatable, Sendable {
    /// `directory` nil means the home. `binding` is pending: the harness process consumes it, so the pane keeps the
    /// id; a fork has none, so its new session is captured.
    case open(command: String, directory: String?, folderMissing: Bool, binding: HarnessBinding?)
    case cannotFork(HarnessID)
    case unavailable(HarnessID)
}

@MainActor
public struct OpenHarnessSession {
    private let registry: HarnessRegistry
    private let directoryExists: (String) -> Bool
    private let clock: () -> Date

    public init(registry: HarnessRegistry, directoryExists: @escaping (String) -> Bool, clock: @escaping () -> Date) {
        self.registry = registry
        self.directoryExists = directoryExists
        self.clock = clock
    }

    public func plan(_ session: HarnessSession, forking: Bool) -> OpenPlan {
        guard let adapter = registry.adapter(for: session.harness) else { return .unavailable(session.harness) }
        let command: String
        if forking {
            guard let fork = adapter.forkCommand(sessionID: session.id) else { return .cannotFork(session.harness) }
            command = fork
        } else {
            command = adapter.resumeCommand(sessionID: session.id)
        }
        let exists = directoryExists(session.directory)
        let binding =
            forking
            ? nil : HarnessBinding(harness: session.harness, sessionID: session.id, processStartedAt: clock(), pid: nil)
        return .open(command: command, directory: exists ? session.directory : nil, folderMissing: !exists, binding: binding)
    }

    public static func folderMissingMessage(_ path: String) -> String { "La carpeta de la sesión ya no existe: \(path)" }

    public static func cannotForkMessage(_ harness: HarnessID) -> String {
        "\(harness.displayName) no permite bifurcar sesiones"
    }
}
