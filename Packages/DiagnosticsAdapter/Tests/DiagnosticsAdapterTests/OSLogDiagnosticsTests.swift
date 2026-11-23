import DiagnosticsAdapter
import Foundation
import OSLog
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("OSLogDiagnostics", .serialized)
struct OSLogDiagnosticsTests {
    private let subsystem = "dev.simonriv.smalti.tests.\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-logs-\(UUID())")

    private func export() throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "registros.log")
        try OSLogDiagnostics(subsystem: subsystem).export(to: file)
        return try String(contentsOf: file, encoding: .utf8)
    }

    @Test func meetsTheContract() throws {
        try DiagnosticLogContract.verify(OSLogDiagnostics(subsystem: subsystem), directory: directory)
    }

    @Test func exportWritesEntriesOfThisProcess() throws {
        let marker = "marca-\(UUID().uuidString)"
        Logger(subsystem: subsystem, category: "tests").error("registro de prueba \(marker, privacy: .public)")

        let text = try export()

        #expect(text.contains(marker))
        #expect(text.contains("tests"))
    }

    @Test func exportLeavesOtherSubsystemsOut() throws {
        let marker = "ajeno-\(UUID().uuidString)"
        Logger(subsystem: "dev.simonriv.other", category: "tests").error("\(marker, privacy: .public)")

        #expect(try !export().contains(marker))
    }

    /// Review Focus 5: what the code logs as private never reaches the exported file.
    @Test func exportedLogsKeepPrivateValuesRedacted() throws {
        let secret = "sk-\(UUID().uuidString)"
        Logger(subsystem: subsystem, category: "tests").error("token \(secret)")

        #expect(try !export().contains(secret))
    }
}
