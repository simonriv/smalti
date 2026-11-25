import Foundation
import SmaltiCore
import Testing

@Suite("Telemetry environment and texts")
struct TelemetryTextsTests {
    private let utc = TimeZone(identifier: "UTC")!  // Safe: "UTC" always exists in the system's zone database.
    // 2027-01-15 10:42 UTC
    private let since = Date(timeIntervalSince1970: 1_800_009_720)

    private func telemetry(requests: Int, errors: Int, durations: [Int], cost: Int) -> SessionTelemetry {
        var ledger = TelemetryLedger()
        ledger.record(
            durations.map {
                .apiRequest(
                    APIRequest(
                        sessionID: "s", sequence: nil, at: since, model: nil, durationMilliseconds: $0, costMicroUSD: 0)
                )
            })
        var value = ledger.telemetry(of: "s") ?? SessionTelemetry(since: since)
        value.requests = requests
        value.errors = errors
        value.costMicroUSD = cost
        return value
    }

    @Test func environmentHasExactlyTheEightVariables() {
        let variables = TelemetryEnvironment.variables(for: TelemetryEndpoint(port: 4318, token: "t"))

        #expect(
            variables == [
                "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
                "OTEL_LOGS_EXPORTER": "otlp",
                "OTEL_METRICS_EXPORTER": "none",
                "OTEL_TRACES_EXPORTER": "none",
                "OTEL_EXPORTER_OTLP_LOGS_PROTOCOL": "http/json",
                "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT": "http://127.0.0.1:4318/v1/logs",
                "OTEL_EXPORTER_OTLP_LOGS_HEADERS": "Authorization=Bearer t",
                "OTEL_LOGS_EXPORT_INTERVAL": "5000",
            ])
    }

    @Test func endpointUsesTheLoopbackLiteral() {
        let endpoint = TelemetryEnvironment.variables(for: TelemetryEndpoint(port: 1, token: "x"))[
            "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"]

        #expect(endpoint?.hasPrefix("http://127.0.0.1:") == true)
    }

    @Test func lineWithPluralsSecondsAndCost() {
        let value = telemetry(requests: 42, errors: 2, durations: [1400], cost: 3_120_000)

        #expect(
            TelemetryTexts.line(value, timeZone: utc)
                == "Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code"
        )
    }

    @Test func lineWithSingularsAndMilliseconds() {
        let value = telemetry(requests: 1, errors: 1, durations: [820], cost: 4_000)

        #expect(
            TelemetryTexts.line(value, timeZone: utc)
                == "Telemetría · desde 10:42 · 1 petición · mediana 820 ms · 1 error de API · $0.00 según Claude Code")
    }

    @Test func lineWithoutErrors() {
        let value = telemetry(requests: 3, errors: 0, durations: [2000], cost: 10_000)

        #expect(TelemetryTexts.line(value, timeZone: utc).contains("· sin errores de API ·"))
    }

    @Test func lineWithoutDurationsOmitsTheMedian() {
        let value = telemetry(requests: 0, errors: 1, durations: [], cost: 0)

        #expect(
            TelemetryTexts.line(value, timeZone: utc)
                == "Telemetría · desde 10:42 · 0 peticiones · 1 error de API · $0.00 según Claude Code")
    }

    @Test(arguments: [(999, "999 ms"), (1000, "1,0 s"), (1049, "1,0 s"), (1050, "1,1 s"), (65_400, "65,4 s")])
    func medianFormatting(milliseconds: Int, text: String) {
        #expect(TelemetryTexts.duration(milliseconds: milliseconds) == text)
    }
}
