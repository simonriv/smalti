/// Why the telemetry receiver could not start.
public enum TelemetryReceiverError: Error, Equatable, Sendable {
    case cannotListen(operation: String, errno: Int32)

    public func message(_ copy: ObservatoryCopy) -> String {
        switch self {
        case .cannotListen(let operation, let errno):
            copy.cannotListen(["operation": operation, "errno": String(errno)])
        }
    }
}

/// Port (F7): Smalti's local OTLP receiver. It listens only on the loopback; each batch of events it decodes reaches
/// `onBatch` on the main actor.
@MainActor
public protocol TelemetryReceiver: AnyObject {
    func start(onBatch: @escaping @MainActor ([TelemetryEvent]) -> Void) throws(TelemetryReceiverError)
        -> TelemetryEndpoint
    func stop()
}

/// Port (F7): whether the user already set Claude Code's telemetry up themselves, so Smalti must not redirect it.
public protocol ClaudeTelemetrySettings: Sendable {
    func isConfiguredByUser() -> Bool
}

/// Where the telemetry stands, as the Observatory's footnote and the tests' probe tell it.
public enum TelemetryStatus: Equatable, Sendable {
    case off
    case configuredByUser
    case listening(TelemetryEndpoint)
    case failed(TelemetryReceiverError)
}

/// What a pane's environment takes from the telemetry: its variables while the receiver listens, none otherwise.
@MainActor
public protocol TelemetryVariablesSource: AnyObject, Sendable {
    func currentVariables() -> [String: String]
}
