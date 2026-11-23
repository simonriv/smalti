import Foundation
import SmaltiCoreTestSupport
import Testing

/// ProjectContextAdapter reads files only: Foundation and the core, never a child process.
@Suite("Project context adapter guard")
struct ProjectContextAdapterGuardTests {
    private let sources = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ProjectContextAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ProjectContextAdapter
        .appending(path: "Sources")

    @Test func onlyFoundationIsImported() throws {
        let violations = try ImportScanner.allowing(["Foundation", "SmaltiCore"]).violations(inDirectory: sources)

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test func noProcessIsUsed() throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path(percentEncoded: false))
        let offenders = try files.filter { $0.hasSuffix(".swift") }.filter { file in
            try String(contentsOf: sources.appending(path: file), encoding: .utf8).contains("Process(")
        }

        #expect(offenders.isEmpty, "\(offenders)")
    }
}
