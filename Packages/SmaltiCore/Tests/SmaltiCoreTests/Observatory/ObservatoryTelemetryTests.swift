import Foundation
import SmaltiCore
import Testing

/// Spec F7: OTLP adds one detail line and its footnote; columns and summary never change.
@Suite("Observatory telemetry")
struct ObservatoryTelemetryTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")
    private let calendar = F.calendar()

    private var session: SessionActivity { F.session("s", [F.turn("a", at: F.date("2026-11-18 09:00"))]) }

    private func ledger(_ session: String = "s") -> TelemetryLedger {
        var ledger = TelemetryLedger()
        ledger.record([
            .apiRequest(
                APIRequest(
                    sessionID: session, sequence: 1, at: F.date("2026-11-18 09:30"), model: nil,
                    durationMilliseconds: 1400, costMicroUSD: 3_120_000)),
            .apiError(
                APIError(sessionID: session, sequence: 2, at: F.date("2026-11-18 09:31"), model: nil, statusCode: 429)),
        ])
        return ledger
    }

    private func report(_ snapshot: ObservatorySnapshot) -> ObservatoryReport {
        ObservatoryReport.make(snapshot, for: .init(period: .today, selection: "s", calendar: calendar))
    }

    @Test func detailShowsTelemetryLineForSessionWithEvents() {
        let snapshot = F.snapshot(sessions: [session], now: now).adding(
            telemetry: ledger(), status: .listening(TelemetryEndpoint(port: 1, token: "t")))

        #expect(
            report(snapshot).detail?.telemetry
                == "Telemetría · desde 09:30 · 1 petición · mediana 1,4 s · 1 error de API · $3.12 según Claude Code")
    }

    @Test func detailWithoutEventsHasNoLine() {
        let snapshot = F.snapshot(sessions: [session], now: now).adding(
            telemetry: ledger("other"), status: .listening(TelemetryEndpoint(port: 1, token: "t")))

        #expect(report(snapshot).detail?.telemetry == nil)
    }

    @Test func columnsAndSummaryUnchangedByTelemetry() {
        let plain = F.snapshot(sessions: [session], now: now)
        let withTelemetry = plain.adding(
            telemetry: ledger(), status: .listening(TelemetryEndpoint(port: 1, token: "t")))

        #expect(report(withTelemetry).summary == report(plain).summary)
        #expect(report(withTelemetry).rows == report(plain).rows)
    }

    @Test func footnoteWithoutTelemetryIsTheF6Text() {
        #expect(
            report(F.snapshot(sessions: [session], now: now)).footnote
                == "Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."
        )
    }

    @Test func footnoteWhileListeningWithoutEventsIsTheF6Text() {
        let snapshot = F.snapshot(sessions: [session], now: now).adding(
            telemetry: TelemetryLedger(), status: .listening(TelemetryEndpoint(port: 1, token: "t")))

        #expect(report(snapshot).footnote == ObservatoryTexts.footnote)
    }

    @Test func footnoteWithTelemetryNamesIt() {
        let snapshot = F.snapshot(sessions: [session], now: now).adding(
            telemetry: ledger(), status: .listening(TelemetryEndpoint(port: 1, token: "t")))

        #expect(
            report(snapshot).footnote
                == "Datos: hooks, transcripts y telemetría de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."
        )
    }

    @Test func footnoteWhenConfiguredOutsideSmalti() {
        let snapshot = F.snapshot(sessions: [session], now: now).adding(
            telemetry: TelemetryLedger(), status: .configuredByUser)

        #expect(
            report(snapshot).footnote
                == "Telemetría de Claude Code configurada fuera de Smalti: no se recibe aquí.")
    }
}
