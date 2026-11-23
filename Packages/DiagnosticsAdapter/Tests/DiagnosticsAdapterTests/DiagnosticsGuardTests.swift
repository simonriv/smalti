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

    /// `privacy: .public` on an interpolation named like a command line, typed text or a buffer.
    private static var publishedInput: Regex<(Substring, Substring)> {
        #/\\\((command|commandLine|line|text|buffer|query|typed)\b[^)]*privacy: \.public/#
    }

    @Test func patternFindsAPublishedCommandLine() {
        #expect("logger.error(\"ran \\(command, privacy: .public)\")".contains(Self.publishedInput))
        #expect(!"logger.error(\"failed \\(reason, privacy: .public)\")".contains(Self.publishedInput))
    }

    @Test func noLoggerPublishesCommandText() {
        let offenders = sources().filter { file in
            (try? String(contentsOf: file, encoding: .utf8))?.contains(Self.publishedInput) ?? false
        }

        #expect(offenders.isEmpty, "publish typed text: \(offenders.map(\.lastPathComponent))")
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
