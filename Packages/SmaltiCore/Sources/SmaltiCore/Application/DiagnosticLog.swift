import Foundation

public enum DiagnosticLogError: Error, Equatable, Sendable {
    case exportFailed(file: String, reason: String)
}

/// Port: what the app logged during this run, saved to a file the user can attach to a report (F4.5). Async and off
/// the main actor: reading a long-running app's log can take seconds.
public protocol DiagnosticLog: Sendable {
    /// Writes `heading` (the build, "Smalti 0.4.5 (abc1234) · macOS 27.2 · Apple M4") and then one line per entry.
    func export(to file: URL, heading: String) async throws(DiagnosticLogError)
}
