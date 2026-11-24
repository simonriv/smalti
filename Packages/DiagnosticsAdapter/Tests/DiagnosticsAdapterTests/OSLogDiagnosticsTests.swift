import DiagnosticsAdapter
import Foundation
import OSLog
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("OSLogDiagnostics", .serialized)
struct OSLogDiagnosticsTests {
    private let subsystem = "dev.simonriv.smalti.tests.\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-logs-\(UUID())")

    private func export() async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "registros.log")
        try await OSLogDiagnostics(subsystem: subsystem).export(to: file, heading: "Smalti 0.4.5 (abc1234)")
        return try String(contentsOf: file, encoding: .utf8)
    }

    @Test func meetsTheContract() async throws {
        try await DiagnosticLogContract.verify(OSLogDiagnostics(subsystem: subsystem), directory: directory)
    }

    @Test func datesAreInLocalTime() async throws {
        Logger(subsystem: subsystem, category: "tests").error("hora local")
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current))
        let offset = stamp.hasSuffix("Z") ? "Z" : String(stamp.suffix(6))

        let entry = try await export().split(separator: "\n").first { $0.contains("hora local") }

        #expect(entry?.contains(offset) == true)
    }

    @Test func exportWritesEntriesOfThisProcess() async throws {
        let marker = "marca-\(UUID().uuidString)"
        Logger(subsystem: subsystem, category: "tests").error("registro de prueba \(marker, privacy: .public)")

        let text = try await export()

        #expect(text.contains(marker))
        #expect(text.contains("tests"))
    }

    @Test func exportLeavesOtherSubsystemsOut() async throws {
        let marker = "ajeno-\(UUID().uuidString)"
        Logger(subsystem: "dev.simonriv.other", category: "tests").error("\(marker, privacy: .public)")

        #expect(try await !export().contains(marker))
    }

    /// Final review: the file goes into a public issue; error descriptions carry working directories, so the user's
    /// home shows as ~.
    @Test func exportShowsTheHomeFolderAsTilde() async throws {
        let marker = "carpeta-\(UUID().uuidString)"
        let home = NSHomeDirectory()
        Logger(subsystem: subsystem, category: "tests").error("cwd \(home + "/" + marker, privacy: .public)")

        let text = try await export()

        #expect(text.contains("~/\(marker)"))
        #expect(!text.contains(home))
    }

    /// Review Focus 5: what the code logs as private never reaches the exported file.
    @Test func exportedLogsKeepPrivateValuesRedacted() async throws {
        let secret = "sk-\(UUID().uuidString)"
        Logger(subsystem: subsystem, category: "tests").error("token \(secret)")

        #expect(try await !export().contains(secret))
    }
}
