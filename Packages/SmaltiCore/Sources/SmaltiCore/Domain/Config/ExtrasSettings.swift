/// `[extras]` in `config.toml` (spec F7): whether panes send Claude Code's telemetry to Smalti's local receiver.
public struct ExtrasSettings: Equatable, Sendable {
    public var otlp: Bool

    public init(otlp: Bool) {
        self.otlp = otlp
    }

    public static let standard = ExtrasSettings(otlp: true)
}
