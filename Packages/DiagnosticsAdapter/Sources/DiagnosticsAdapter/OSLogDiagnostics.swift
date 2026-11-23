import Foundation
import OSLog
import SmaltiCore

/// `DiagnosticLog` over the unified log: this process's entries of one subsystem, since the app started. What the
/// code logged as private stays redacted. One line per entry: `fecha · categoría · nivel · mensaje`.
@MainActor
public final class OSLogDiagnostics: DiagnosticLog {
    private let subsystem: String

    public init(subsystem: String) {
        self.subsystem = subsystem
    }

    public func export(to file: URL) throws(DiagnosticLogError) {
        let path = file.path(percentEncoded: false)
        let lines: [String]
        do {
            lines = try entries()
        } catch {
            throw .exportFailed(file: path, reason: "the unified log could not be read: \(error.localizedDescription)")
        }
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw .exportFailed(file: path, reason: error.localizedDescription)
        }
    }

    private func entries() throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        return try store.getEntries(matching: predicate).compactMap { $0 as? OSLogEntryLog }.map(Self.line)
    }

    private static func line(_ entry: OSLogEntryLog) -> String {
        let date = entry.date.formatted(.iso8601)
        return [date, entry.category, level(entry.level), entry.composedMessage].joined(separator: " · ")
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "?"
        }
    }
}
