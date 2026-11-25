/// Where a pane's Claude Code sends its telemetry: Smalti's receiver on the loopback, with its secret.
public struct TelemetryEndpoint: Equatable, Sendable {
    public let port: UInt16
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }
}

/// The variables that make a pane's Claude Code send its log events, and only them, to Smalti (spec F7).
public enum TelemetryEnvironment {
    /// Always the literal loopback address: a name could resolve to another interface.
    static let loopback = "127.0.0.1"

    public static func variables(for endpoint: TelemetryEndpoint) -> [String: String] {
        [
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_LOGS_EXPORTER": "otlp",
            "OTEL_METRICS_EXPORTER": "none",
            "OTEL_TRACES_EXPORTER": "none",
            "OTEL_EXPORTER_OTLP_LOGS_PROTOCOL": "http/json",
            "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT": "http://\(loopback):\(endpoint.port)/v1/logs",
            "OTEL_EXPORTER_OTLP_LOGS_HEADERS": "Authorization=Bearer \(endpoint.token)",
            "OTEL_LOGS_EXPORT_INTERVAL": "5000",
        ]
    }
}
