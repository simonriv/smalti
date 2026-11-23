import Foundation

public enum DiagnosticLogError: Error, Equatable, Sendable {
    case exportFailed(file: String, reason: String)
}

/// Port: what the app logged during this run, saved to a file the user can attach to a report (F4.5).
@MainActor
public protocol DiagnosticLog: AnyObject {
    func export(to file: URL) throws(DiagnosticLogError)
}
