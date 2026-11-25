import Foundation

/// The telemetry line of the Observatory's session detail (spec F7).
public enum TelemetryTexts {
    /// "Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code".
    public static func line(_ telemetry: SessionTelemetry, timeZone: TimeZone) -> String {
        var parts = [
            "Telemetría", "desde \(ObservatoryFormat.clock(telemetry.since, timeZone: timeZone))",
            "\(telemetry.requests) \(telemetry.requests == 1 ? "petición" : "peticiones")",
        ]
        if let median = telemetry.medianMilliseconds { parts.append("mediana \(duration(milliseconds: median))") }
        parts.append(errors(telemetry.errors))
        parts.append("\(ObservatoryFormat.usd(Double(telemetry.costMicroUSD) / 1_000_000)) según Claude Code")
        return parts.joined(separator: " · ")
    }

    /// "820 ms" under a second, "1,4 s" (one decimal, comma) from a second up.
    public static func duration(milliseconds: Int) -> String {
        guard milliseconds >= 1000 else { return "\(milliseconds) ms" }
        let tenths = (milliseconds + 50) / 100
        return "\(tenths / 10),\(tenths % 10) s"
    }

    private static func errors(_ count: Int) -> String {
        switch count {
        case 0: "sin errores de API"
        case 1: "1 error de API"
        default: "\(count) errores de API"
        }
    }
}
