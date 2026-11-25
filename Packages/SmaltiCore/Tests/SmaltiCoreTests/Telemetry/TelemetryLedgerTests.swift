import Foundation
import SmaltiCore
import Testing

@Suite("Telemetry ledger")
struct TelemetryLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(
        _ session: String = "s1", sequence: Int? = nil, after seconds: TimeInterval = 0, duration: Int = 1000,
        cost: Int = 10_000
    ) -> TelemetryEvent {
        .apiRequest(
            APIRequest(
                sessionID: session, sequence: sequence, at: start.addingTimeInterval(seconds), model: "opus",
                durationMilliseconds: duration, costMicroUSD: cost))
    }

    private func error(_ session: String = "s1", sequence: Int? = nil, status: Int? = 429) -> TelemetryEvent {
        .apiError(APIError(sessionID: session, sequence: sequence, at: start, model: "opus", statusCode: status))
    }

    @Test func emptyLedgerHasNoSessions() {
        let ledger = TelemetryLedger()

        #expect(ledger.isEmpty)
        #expect(ledger.telemetry(of: "s1") == nil)
    }

    @Test func ledgerCountsRequestsAndCost() {
        var ledger = TelemetryLedger()

        ledger.record([request(cost: 12_300), request(cost: 700)])

        let telemetry = ledger.telemetry(of: "s1")
        #expect(telemetry?.requests == 2)
        #expect(telemetry?.costMicroUSD == 13_000)
        #expect(!ledger.isEmpty)
    }

    @Test func ledgerCountsErrorsByStatus() {
        var ledger = TelemetryLedger()

        ledger.record([error(status: 429), error(status: 429), error(status: 529), error(status: nil)])

        let telemetry = ledger.telemetry(of: "s1")
        #expect(telemetry?.errors == 4)
        #expect(telemetry?.errorsByStatus == [429: 2, 529: 1])
        #expect(telemetry?.requests == 0)
    }

    @Test func ledgerKeepsSessionsApart() {
        var ledger = TelemetryLedger()

        ledger.record([request("a"), request("b"), request("b")])

        #expect(ledger.telemetry(of: "a")?.requests == 1)
        #expect(ledger.telemetry(of: "b")?.requests == 2)
    }

    @Test func ledgerIgnoresRepeatedSequence() {
        var ledger = TelemetryLedger()

        ledger.record([request(sequence: 7), error(sequence: 8)])
        ledger.record([request(sequence: 7), error(sequence: 8), request(sequence: 9)])

        #expect(ledger.telemetry(of: "s1")?.requests == 2)
        #expect(ledger.telemetry(of: "s1")?.errors == 1)
    }

    @Test func sameSequenceInAnotherSessionCounts() {
        var ledger = TelemetryLedger()

        ledger.record([request("a", sequence: 1), request("b", sequence: 1)])

        #expect(ledger.telemetry(of: "b")?.requests == 1)
    }

    @Test func ledgerKeepsEventsWithoutSequence() {
        var ledger = TelemetryLedger()

        ledger.record([request(), request()])

        #expect(ledger.telemetry(of: "s1")?.requests == 2)
    }

    @Test func ledgerSinceIsEarliestEvent() {
        var ledger = TelemetryLedger()

        ledger.record([request(after: 60), request(after: 5), request(after: 120)])

        #expect(ledger.telemetry(of: "s1")?.since == start.addingTimeInterval(5))
    }

    @Test(arguments: [
        ([1000], 1000), ([1000, 3000], 2000), ([500, 900, 4000], 900), ([1, 2, 3, 100], 3),
    ])
    func medianOfOddAndEven(durations: [Int], median: Int) {
        var ledger = TelemetryLedger()

        ledger.record(durations.map { request(duration: $0) })

        #expect(ledger.telemetry(of: "s1")?.medianMilliseconds == median)
    }

    @Test func medianUsesOnlyTheLatest200Durations() {
        var ledger = TelemetryLedger()

        ledger.record(Array(repeating: request(duration: 99_000), count: 101))
        ledger.record(Array(repeating: request(duration: 10), count: 200))

        #expect(ledger.telemetry(of: "s1")?.medianMilliseconds == 10)
        #expect(ledger.telemetry(of: "s1")?.requests == 301)
    }

    @Test func medianOfOnlyErrorsIsNil() {
        var ledger = TelemetryLedger()

        ledger.record([error()])

        #expect(ledger.telemetry(of: "s1")?.medianMilliseconds == nil)
    }

    @Test func ledgerDropsOldestSessionPast200() {
        var ledger = TelemetryLedger()
        let sessions = (0...TelemetryLedger.sessionLimit).map { request("s\($0)", after: TimeInterval($0)) }

        ledger.record(sessions)

        #expect(ledger.telemetry(of: "s0") == nil)
        #expect(ledger.telemetry(of: "s1") != nil)
        #expect(ledger.telemetry(of: "s\(TelemetryLedger.sessionLimit)") != nil)
    }

    @Test func ledgerKeepsAnActiveOldSession() {
        var ledger = TelemetryLedger()
        ledger.record([request("s0", after: 0)])
        ledger.record((1..<TelemetryLedger.sessionLimit).map { request("s\($0)", after: TimeInterval($0)) })

        ledger.record([request("s0", after: 1_000), request("new", after: 1_001)])

        #expect(ledger.telemetry(of: "s0") != nil)
        #expect(ledger.telemetry(of: "s1") == nil)
    }
}
