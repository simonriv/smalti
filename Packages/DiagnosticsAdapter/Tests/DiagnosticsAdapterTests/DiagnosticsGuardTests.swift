import Foundation
import Testing

/// F4.5: only DiagnosticsAdapter reads the unified log, and no `Logger` publishes what a user typed.
@Suite("Diagnostics guard")
struct DiagnosticsGuardTests {
    private static let skipped = ["/.build/", "/build/", "/.git/", "/vendor/", "/.superpowers/", "/node_modules/"]
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()  // DiagnosticsAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DiagnosticsAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    /// `privacy: .public` on an interpolation whose path names a command line, typed text or a buffer, anywhere in it
    /// (`command`, `command.arguments`, `pane.commandLine`, `command.joined(…)`). Word ends are ASCII on purpose:
    /// Swift's default Unicode word boundary treats `command.rawValue` as one word.
    private static var publishedInput: Regex<(Substring, Substring)> {
        #/\\\((?:[A-Za-z0-9_]+\.)*(command|commandLine|line|text|buffer|query|typed)(?![A-Za-z0-9_])[^\n]*privacy: \.public/#
    }

    @Test(arguments: [
        "logger.error(\"ran \\(command, privacy: .public)\")",
        "logger.error(\"ran \\(command.arguments, privacy: .public)\")",
        "logger.error(\"ran \\(pane.commandLine, privacy: .public)\")",
        "logger.error(\"ran \\(command.joined(separator: \" \"), privacy: .public)\")",
        "logger.error(\"typed \\(line.text, privacy: .public)\")",
    ])
    func patternFindsAPublishedCommandLine(_ source: String) {
        #expect(source.contains(Self.publishedInput))
    }

    @Test(arguments: [
        "logger.error(\"failed \\(reason, privacy: .public)\")",
        "logger.error(\"ran \\(command, privacy: .private)\")",
        "logger.error(\"unknown \\(commands, privacy: .public)\")",
    ])
    func patternLeavesOtherValuesAlone(_ source: String) {
        #expect(!source.contains(Self.publishedInput))
    }

    @Test func noLoggerPublishesCommandText() {
        let offenders = sources().flatMap { file in
            let lines =
                (try? String(contentsOf: file, encoding: .utf8))?.split(
                    separator: "\n", omittingEmptySubsequences: false) ?? []
            return lines.enumerated().filter { $0.element.contains(Self.publishedInput) }.map { number, _ in
                "\(file.path(percentEncoded: false)):\(number + 1)"
            }
        }

        #expect(offenders.isEmpty, "publish typed text:\n\(offenders.joined(separator: "\n"))")
    }

    @Test func onlyThisAdapterReadsTheUnifiedLog() {
        let readers = sources().filter { file in
            !file.path(percentEncoded: false).contains("/Packages/DiagnosticsAdapter/")
                && ((try? String(contentsOf: file, encoding: .utf8))?.contains("OSLogStore") ?? false)
        }

        #expect(readers.isEmpty, "read the unified log: \(readers.map(\.lastPathComponent))")
    }

    private func sources() -> [URL] {
        ["App", "Packages"].flatMap { folder in
            let enumerator = FileManager.default.enumerator(
                at: root.appending(path: folder), includingPropertiesForKeys: nil)
            var found: [URL] = []
            while let url = enumerator?.nextObject() as? URL {
                let path = url.path(percentEncoded: false)
                guard url.pathExtension == "swift", !Self.skipped.contains(where: path.contains),
                    !path.contains("/Tests/")
                else { continue }
                found.append(url)
            }
            return found
        }
    }
}
