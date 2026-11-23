import Foundation
import SmaltiCore

/// Writes fixed lines; for use cases and app tests that must not read the real unified log.
@MainActor
public final class FakeDiagnosticLog: DiagnosticLog {
    public var lines: [String]
    public private(set) var exports: [URL] = []

    public init(lines: [String] = ["2026-11-23 10:00:00 · tests · error · listo"]) {
        self.lines = lines
    }

    public func export(to file: URL) throws(DiagnosticLogError) {
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw .exportFailed(file: file.path(percentEncoded: false), reason: error.localizedDescription)
        }
        exports.append(file)
    }
}
