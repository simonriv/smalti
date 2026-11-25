import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Collect telemetry")
struct CollectTelemetryTests {
    private let receiver = FakeTelemetryReceiver()
    private let on = ExtrasSettings(otlp: true)
    private let off = ExtrasSettings(otlp: false)

    private func collector(configuredByUser: Bool = false) -> CollectTelemetry {
        CollectTelemetry(receiver: receiver, settings: FakeClaudeTelemetrySettings(isConfigured: configuredByUser))
    }

    private func request(_ session: String = "s1") -> TelemetryEvent {
        .apiRequest(
            APIRequest(
                sessionID: session, sequence: nil, at: Date(timeIntervalSince1970: 0), model: nil,
                durationMilliseconds: 900, costMicroUSD: 5))
    }

    @Test func startsOffWithoutVariables() {
        let collector = collector()

        #expect(collector.status == .off)
        #expect(collector.currentVariables().isEmpty)
        #expect(receiver.starts == 0)
    }

    @Test func applyOnStartsAndListens() {
        let collector = collector()

        collector.apply(on)

        #expect(collector.status == .listening(receiver.endpoint))
        #expect(collector.currentVariables() == TelemetryEnvironment.variables(for: receiver.endpoint))
        #expect(receiver.starts == 1)
    }

    @Test func applyOnTwiceStartsOnce() {
        let collector = collector()

        collector.apply(on)
        collector.apply(on)

        #expect(receiver.starts == 1)
    }

    @Test func applyOffStopsAndClearsVariables() {
        let collector = collector()
        collector.apply(on)

        collector.apply(off)

        #expect(collector.status == .off)
        #expect(collector.currentVariables().isEmpty)
        #expect(receiver.stops == 1)
    }

    @Test func applyOffWhileOffDoesNotStop() {
        let collector = collector()

        collector.apply(off)

        #expect(receiver.stops == 0)
    }

    @Test func configuredByUserNeverStarts() {
        let collector = collector(configuredByUser: true)

        collector.apply(on)

        #expect(collector.status == .configuredByUser)
        #expect(collector.currentVariables().isEmpty)
        #expect(receiver.starts == 0)
    }

    @Test func startFailureReportsFailedAndNoVariables() {
        receiver.failNextStart = .cannotListen(operation: "bind", errno: 48)
        let collector = collector()

        collector.apply(on)

        #expect(collector.status == .failed(TelemetryReceiverError.cannotListen(operation: "bind", errno: 48).message))
        #expect(collector.currentVariables().isEmpty)
    }

    @Test func failedReceiverRetriesOnTheNextApply() {
        receiver.failNextStart = .cannotListen(operation: "bind", errno: 48)
        let collector = collector()
        collector.apply(on)

        collector.apply(on)

        #expect(collector.status == .listening(receiver.endpoint))
    }

    @Test func reconfigureStopsAndRestarts() {
        let collector = collector()
        collector.apply(on)
        receiver.send([request()])

        collector.apply(off)
        collector.apply(on)

        #expect(receiver.starts == 2)
        #expect(collector.ledger.telemetry(of: "s1")?.requests == 1)
    }

    @Test func batchesFoldIntoLedgerAndNotify() {
        let collector = collector()
        var changes = 0
        collector.onChange = { changes += 1 }
        collector.apply(on)

        receiver.send([request(), request("s2")])

        #expect(collector.ledger.telemetry(of: "s1")?.requests == 1)
        #expect(collector.ledger.telemetry(of: "s2")?.requests == 1)
        #expect(changes == 2)
    }

    @Test func statusChangesNotify() {
        let collector = collector()
        var changes = 0
        collector.onChange = { changes += 1 }

        collector.apply(on)
        collector.apply(off)

        #expect(changes == 2)
    }

    @Test func paneEnvironmentAddsTelemetryVariables() {
        let collector = collector()
        collector.apply(on)

        let variables = PaneEnvironment(version: "7", telemetry: collector).variables(for: PaneID())

        #expect(variables["OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"] == "http://127.0.0.1:4318/v1/logs")
        #expect(variables["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1")
    }

    @Test func paneEnvironmentWithoutListeningAddsNone() {
        let variables = PaneEnvironment(version: "7", telemetry: collector()).variables(for: PaneID())

        #expect(variables.keys.filter { $0.hasPrefix("OTEL_") || $0.hasPrefix("CLAUDE_") }.isEmpty)
    }

    @Test func smaltiVariablesStillWin() {
        let source = FixedTelemetryVariables(["SMALTI": "0", "SMALTI_VERSION": "x", "OTEL_LOGS_EXPORTER": "otlp"])

        let variables = PaneEnvironment(version: "7", extra: ["OTEL_LOGS_EXPORTER": "none"], telemetry: source)
            .variables(for: PaneID())

        #expect(variables["SMALTI"] == "1")
        #expect(variables["SMALTI_VERSION"] == "7")
        #expect(variables["OTEL_LOGS_EXPORTER"] == "otlp")
    }
}

@MainActor
private final class FixedTelemetryVariables: TelemetryVariablesSource {
    private let variables: [String: String]

    init(_ variables: [String: String]) {
        self.variables = variables
    }

    func currentVariables() -> [String: String] { variables }
}
