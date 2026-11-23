import Foundation
import SmaltiCore
import Testing

/// What every `DiagnosticLog` does: it writes a file where asked, starting with the heading, and names the file when
/// it cannot.
public enum DiagnosticLogContract {
    public static func verify(_ log: some DiagnosticLog, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "contract-\(UUID().uuidString).log")
        try await log.export(to: file, heading: "Smalti 0.4.5 (abc1234)")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("Smalti 0.4.5 (abc1234)\n"), "the export starts with the heading")

        let unwritable = directory.appending(path: "missing-\(UUID().uuidString)/registros.log")
        do {
            try await log.export(to: unwritable, heading: "")
            Issue.record("an unwritable place must be an error")
        } catch {
            guard case .exportFailed(let path, _) = error else { return }
            #expect(path == unwritable.path(percentEncoded: false), "the error names the file")
        }
    }
}
