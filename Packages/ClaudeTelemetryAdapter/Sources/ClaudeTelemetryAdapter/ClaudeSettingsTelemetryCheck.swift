import Foundation
import SmaltiCore
import os

/// Whether the user already set Claude Code's telemetry up (spec F7, amendment 7): the `env` block of their
/// `settings.json` or of the managed settings, or Smalti's own process environment (which every pane inherits), names
/// `CLAUDE_CODE_ENABLE_TELEMETRY` or any `OTEL_` variable. A repository's `.claude/settings.json` does not count:
/// Claude ignores exporter variables there.
public struct ClaudeSettingsTelemetryCheck: ClaudeTelemetrySettings {
    public static let defaultManagedSettings = URL(
        filePath: "/Library/Application Support/ClaudeCode/managed-settings.json")
    private static let log = Logger(subsystem: "dev.simonriv.smalti", category: "telemetry")

    private let files: [URL]
    private let environment: [String: String]

    public init(
        claudeHome: URL, managedSettings: URL = Self.defaultManagedSettings,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        files = [claudeHome.appending(path: "settings.json"), managedSettings]
        self.environment = environment
    }

    public func isConfiguredByUser() -> Bool {
        environment.keys.contains(where: Self.isTelemetryVariable)
            || files.contains { Self.environment(in: $0).keys.contains(where: Self.isTelemetryVariable) }
    }

    private static func isTelemetryVariable(_ name: String) -> Bool {
        name == "CLAUDE_CODE_ENABLE_TELEMETRY" || name.hasPrefix("OTEL_")
    }

    /// The file's `env` object; empty when the file is missing or unreadable (logged, never fatal).
    private static func environment(in file: URL) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return [:] }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            return ((object as? [String: Any])?["env"] as? [String: Any]) ?? [:]
        } catch {
            log.error(
                "claude settings unreadable \(file.path(percentEncoded: false), privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            return [:]
        }
    }
}
