import ClaudeTelemetryAdapter
import Foundation
import Testing

/// Spec F7: Smalti never redirects telemetry the user already set up in Claude's own settings.
@Suite("Claude settings telemetry check")
struct ClaudeSettingsTelemetryCheckTests {
    private let home = FileManager.default.temporaryDirectory.appending(path: "smalti-claude-\(UUID())")
    private var managed: URL { home.appending(path: "managed-settings.json") }

    private func write(_ json: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
    }

    private var check: ClaudeSettingsTelemetryCheck {
        ClaudeSettingsTelemetryCheck(claudeHome: home, managedSettings: managed)
    }

    @Test func noSettingsIsNotConfigured() {
        #expect(!check.isConfiguredByUser())
    }

    @Test func envWithOtelEndpointIsConfigured() throws {
        try write(
            #"{"env":{"OTEL_EXPORTER_OTLP_ENDPOINT":"https://collector.example"}}"#,
            to: home.appending(path: "settings.json"))

        #expect(check.isConfiguredByUser())
    }

    @Test func envWithEnableTelemetryIsConfigured() throws {
        try write(#"{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"1"}}"#, to: home.appending(path: "settings.json"))

        #expect(check.isConfiguredByUser())
    }

    @Test func managedSettingsCount() throws {
        try write(#"{"env":{"OTEL_LOGS_EXPORTER":"otlp"}}"#, to: managed)

        #expect(check.isConfiguredByUser())
    }

    @Test func otherEnvKeysDoNotCount() throws {
        try write(
            #"{"env":{"ANTHROPIC_MODEL":"opus","MY_OTEL_THING":"x"},"OTEL_EXPORTER_OTLP_ENDPOINT":"top-level"}"#,
            to: home.appending(path: "settings.json"))

        #expect(!check.isConfiguredByUser())
    }

    @Test func malformedSettingsDoesNotCount() throws {
        try write("{not json", to: home.appending(path: "settings.json"))
        try write(#"{"env":"OTEL_LOGS_EXPORTER"}"#, to: managed)

        #expect(!check.isConfiguredByUser())
    }

    @Test func processEnvironmentWithOtelIsConfigured() {
        let check = ClaudeSettingsTelemetryCheck(
            claudeHome: home, managedSettings: managed, environment: ["OTEL_EXPORTER_OTLP_ENDPOINT": "https://x"])

        #expect(check.isConfiguredByUser())
    }

    @Test func processEnvironmentWithoutTelemetryIsNot() {
        let check = ClaudeSettingsTelemetryCheck(
            claudeHome: home, managedSettings: managed, environment: ["PATH": "/bin", "MY_OTEL": "x"])

        #expect(!check.isConfiguredByUser())
    }
}
