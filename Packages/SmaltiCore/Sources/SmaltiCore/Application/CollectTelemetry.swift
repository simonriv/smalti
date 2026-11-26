/// Runs Smalti's side of Claude Code's telemetry (spec F7): starts or stops the receiver as `[extras] otlp` says,
/// hands panes the variables that point their Claude at it, and folds what arrives into the ledger. It never starts
/// when the user set Claude's telemetry up themselves.
@MainActor
public final class CollectTelemetry: TelemetryVariablesSource {
    private let receiver: any TelemetryReceiver
    private let settings: any ClaudeTelemetrySettings
    public private(set) var status = TelemetryStatus.off
    /// Kept across stops: what was received stays readable while the app is open.
    public private(set) var ledger = TelemetryLedger()
    /// Called after the status or the ledger changed.
    public var onChange: (() -> Void)?

    public init(receiver: any TelemetryReceiver, settings: any ClaudeTelemetrySettings) {
        self.receiver = receiver
        self.settings = settings
    }

    public func apply(_ extras: ExtrasSettings) {
        if extras.otlp { turnOn() } else { turnOff() }
    }

    public func currentVariables() -> [String: String] {
        guard case .listening(let endpoint) = status else { return [:] }
        return TelemetryEnvironment.variables(for: endpoint)
    }

    /// Asks the user's settings every time: a configuration that appeared or went away since the last apply wins.
    private func turnOn() {
        if settings.isConfiguredByUser() {
            if case .listening = status { receiver.stop() }
            if status != .configuredByUser { change(to: .configuredByUser) }
            return
        }
        if case .listening = status { return }
        do {
            let endpoint = try receiver.start { [weak self] events in self?.record(events) }
            change(to: .listening(endpoint))
        } catch {
            change(to: .failed(error))
        }
    }

    private func turnOff() {
        if case .listening = status { receiver.stop() }
        if status != .off { change(to: .off) }
    }

    private func record(_ events: [TelemetryEvent]) {
        ledger.record(events)
        onChange?()
    }

    private func change(to status: TelemetryStatus) {
        self.status = status
        onChange?()
    }
}
