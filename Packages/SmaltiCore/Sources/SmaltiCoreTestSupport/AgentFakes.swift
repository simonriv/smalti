import SmaltiCore

@MainActor
public final class FakeTelemetrySource: TelemetrySource {
    private let stream = AsyncStream<AgentEvent>.makeStream()

    public init() {}

    public func events() -> AsyncStream<AgentEvent> { stream.stream }

    public func send(_ event: AgentEvent) {
        stream.continuation.yield(event)
    }
}

@MainActor
public final class RecordingNotifier: Notifier {
    public private(set) var delivered: [AttentionNotice] = []

    public init() {}

    public func notify(_ notice: AttentionNotice) {
        delivered.append(notice)
    }
}

@MainActor
public final class FakeHarnessIntegration: HarnessIntegration {
    public var failure: IntegrationError?
    /// The harness is not installed: its state cannot be known.
    public var isMissing = false
    private var installed = false

    public init() {}

    public func install() async throws(IntegrationError) {
        if let failure { throw failure }
        installed = true
    }

    public func uninstall() async throws(IntegrationError) {
        if let failure { throw failure }
        installed = false
    }

    public var installState: IntegrationState {
        if isMissing { return .unknown }
        return installed ? .installed : .notInstalled
    }
}
