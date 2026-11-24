import Foundation
import SmaltiCoreTestSupport
import Testing

/// ProjectContextAdapter reads files for the keystroke path; only `CommandRunner.swift` starts processes (F5: `git
/// status` and `--version` for the prompt, spec F5), and only `FilePromptFacts` uses it.
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
        let offenders = try files.filter { $0.hasSuffix(".swift") && !$0.hasSuffix("/CommandRunner.swift") }.filter { file in
            try String(contentsOf: sources.appending(path: file), encoding: .utf8).contains("Process(")
        }

        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func theKeystrokePathNeverRunsCommands() throws {
        let source = try String(contentsOf: sources.appending(path: "ProjectContextAdapter/FileProjectContext.swift"), encoding: .utf8)

        #expect(!source.contains("CommandRunner"))
    }
}
