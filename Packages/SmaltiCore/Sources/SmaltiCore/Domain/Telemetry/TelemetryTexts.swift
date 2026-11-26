import Foundation

/// The telemetry line of the Observatory's session detail (spec F7).
public enum TelemetryTexts {
    /// "Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code".
    public static func line(_ telemetry: SessionTelemetry, timeZone: TimeZone, copy: TelemetryCopy) -> String {
        var parts = [
            copy.title, copy.since(["clock": ObservatoryFormat.clock(telemetry.since, timeZone: timeZone)]),
            copy.requests(telemetry.requests),
        ]
        if let median = telemetry.medianMilliseconds {
            parts.append(copy.median(["duration": duration(milliseconds: median, copy: copy)]))
        }
        parts.append(telemetry.errors == 0 ? copy.noErrors : copy.errors(telemetry.errors))
        parts.append(copy.cost(["usd": ObservatoryFormat.usd(Double(telemetry.costMicroUSD) / 1_000_000)]))
        return parts.joined(separator: " · ")
    }

    /// "820 ms" under a second, "1,4 s" (one decimal, the language's separator) from a second up.
    public static func duration(milliseconds: Int, copy: TelemetryCopy) -> String {
        guard milliseconds >= 1000 else { return "\(milliseconds) ms" }
        let tenths = (milliseconds + 50) / 100
        return "\(tenths / 10)\(copy.decimalSeparator)\(tenths % 10) s"
    }
}
