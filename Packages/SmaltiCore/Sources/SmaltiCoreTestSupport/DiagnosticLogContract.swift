import Foundation
import SmaltiCore
import Testing

/// What every `DiagnosticLog` does: it writes a file where asked, and names the file when it cannot.
@MainActor
public enum DiagnosticLogContract {
    public static func verify(_ log: some DiagnosticLog, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "contract-\(UUID().uuidString).log")
        try log.export(to: file)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), "the export exists")

        let unwritable = directory.appending(path: "missing-\(UUID().uuidString)/registros.log")
        #expect(throws: DiagnosticLogError.self, "an unwritable place is an error") { try log.export(to: unwritable) }
        do {
            try log.export(to: unwritable)
        } catch {
            guard case .exportFailed(let path, _) = error else { return }
            #expect(path == unwritable.path(percentEncoded: false), "the error names the file")
        }
    }
}
