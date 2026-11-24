import Foundation
import SmaltiCore

/// Writes fixed lines; for use cases and app tests that must not read the real unified log.
public actor FakeDiagnosticLog: DiagnosticLog {
    public let lines: [String]
    public private(set) var exports: [URL] = []

    public init(lines: [String] = ["2026-11-23T10:00:00-05:00 · tests · error · listo"]) {
        self.lines = lines
    }

    public func export(to file: URL, heading: String) async throws(DiagnosticLogError) {
        do {
            try ([heading] + lines).joined(separator: "\n").appending("\n").write(
                to: file, atomically: true, encoding: .utf8)
        } catch {
            throw .exportFailed(file: file.path(percentEncoded: false), reason: error.localizedDescription)
        }
        exports.append(file)
    }
}
