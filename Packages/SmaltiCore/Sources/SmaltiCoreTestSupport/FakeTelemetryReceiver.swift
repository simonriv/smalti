import SmaltiCore

/// A receiver that listens nowhere: `send` delivers a batch as the real one would.
@MainActor
public final class FakeTelemetryReceiver: TelemetryReceiver {
    public let endpoint = TelemetryEndpoint(port: 4318, token: "fake-token")
    public var failNextStart: TelemetryReceiverError?
    public private(set) var starts = 0
    public private(set) var stops = 0
    private var onBatch: (@MainActor ([TelemetryEvent]) -> Void)?

    public init() {}

    public func start(onBatch: @escaping @MainActor ([TelemetryEvent]) -> Void) throws(TelemetryReceiverError)
        -> TelemetryEndpoint
    {
        if let failure = failNextStart {
            failNextStart = nil
            throw failure
        }
        starts += 1
        self.onBatch = onBatch
        return endpoint
    }

    public func stop() {
        stops += 1
        onBatch = nil
    }

    public func send(_ events: [TelemetryEvent]) { onBatch?(events) }
}

public struct FakeClaudeTelemetrySettings: ClaudeTelemetrySettings {
    private let isConfigured: Bool

    public init(isConfigured: Bool) {
        self.isConfigured = isConfigured
    }

    public func isConfiguredByUser() -> Bool { isConfigured }
}
