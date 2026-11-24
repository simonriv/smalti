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

    /// `privacy: .public` on an interpolation, even one split over lines, whose path names a command line, its
    /// arguments, typed text or a buffer (`command`, `pane.foregroundCommandLine`, `argv`, `cmd`, `line.text`,
    /// `command.joined(…)`). Word ends are ASCII on purpose: Swift's default Unicode word boundary treats
    /// `command.rawValue` as one word.
    private static var publishedInput: Regex<Substring> {
        #/\\\(\s*(?:[A-Za-z0-9_]+\.)*(?i:[A-Za-z0-9_]*(?:commandline|command|cmd|argv|arguments|args|typed|buffer|query)|line|text)(?![A-Za-z0-9_])(?:[^()]|\([^()]*\))*privacy: \.public/#
    }

    @Test(arguments: [
        "logger.error(\"ran \\(command, privacy: .public)\")",
        "logger.error(\"ran \\(command.arguments, privacy: .public)\")",
        "logger.error(\"ran \\(pane.commandLine, privacy: .public)\")",
        "logger.error(\"ran \\(command.joined(separator: \" \"), privacy: .public)\")",
        "logger.error(\"typed \\(line.text, privacy: .public)\")",
        "logger.error(\"ran \\(pane.foregroundCommandLine, privacy: .public)\")",
        "logger.error(\"ran \\(argv, privacy: .public)\")",
        "logger.error(\"ran \\(cmd, privacy: .public)\")",
        "logger.error(\"ran \\(\n    pane.commandLine,\n    privacy: .public)\")",
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
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return text.matches(of: Self.publishedInput).map { match in
                let line = text[..<match.range.lowerBound].count { $0 == "\n" } + 1
                return "\(file.path(percentEncoded: false)):\(line)"
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
