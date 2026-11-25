/// Port: where agent events come from (the hooks, through the IPC socket).
@MainActor
public protocol TelemetrySource: AnyObject {
    /// One consumer: iterate it once.
    func events() -> AsyncStream<AgentEvent>
}

/// Port: shows a notice to the user outside the window (macOS notifications).
@MainActor
public protocol Notifier: AnyObject {
    func notify(_ notice: AttentionNotice)
}

public enum IntegrationError: Error, Equatable, Sendable {
    case commandFailed(command: String, output: String)
    case harnessMissing(binary: String)
}

/// Port: installs and removes Smalti's integration in a harness (the Claude Code plugin).
@MainActor
public protocol HarnessIntegration: AnyObject {
    func install() async throws(IntegrationError)
    func uninstall() async throws(IntegrationError)
    var installState: IntegrationState { get async }
}
