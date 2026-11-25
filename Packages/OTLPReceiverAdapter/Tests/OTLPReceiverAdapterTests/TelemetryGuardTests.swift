import Foundation
import Testing

/// F7 C10: only the OTLP receiver opens TCP sockets in the app's code, the telemetry adapters never publish what they
/// read, and the machine's managed Claude settings are named in one place only, as a default a test can replace.
@Suite("Telemetry guard")
struct TelemetryGuardTests {
    private static let skipped = ["/.build/", "/build/", "/.git/", "/vendor/", "/.superpowers/", "/node_modules/"]
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()  // OTLPReceiverAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // OTLPReceiverAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
    private static let isInRepository = FileManager.default.fileExists(
        atPath: root.appending(path: "App/Smalti").path(percentEncoded: false))

    /// Production Swift files: the app and every package's `Sources`, never tests.
    private static func productionFiles() -> [(path: String, text: String)] {
        let roots = [root.appending(path: "App/Smalti"), root.appending(path: "Packages")]
        return roots.flatMap { folder -> [(String, String)] in
            let paths =
                FileManager.default.enumerator(atPath: folder.path(percentEncoded: false))?
                .compactMap { $0 as? String } ?? []
            return paths.compactMap { relative in
                let path = folder.appending(path: relative).path(percentEncoded: false)
                guard path.hasSuffix(".swift"), !skipped.contains(where: path.contains),
                    folder.lastPathComponent != "Packages" || relative.contains("/Sources/"),
                    let text = try? String(contentsOfFile: path, encoding: .utf8)
                else { return nil }
                return (path, text)
            }
        }
    }

    static func lines(matching pattern: String, in files: [(path: String, text: String)]) -> [String] {
        files.flatMap { file in
            file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                .filter { $0.element.contains(pattern) }
                .map { "\(file.path):\($0.offset + 1)" }
        }
    }

    @Test(.enabled(if: isInRepository))
    func onlyTheOTLPReceiverOpensTCPSockets() {
        let offenders = Self.lines(matching: "AF_INET", in: Self.productionFiles())
            .filter { !$0.contains("/Packages/OTLPReceiverAdapter/Sources/") }

        #expect(offenders.isEmpty, "TCP sockets outside OTLPReceiverAdapter: \(offenders)")
    }

    @Test(.enabled(if: isInRepository))
    func telemetryAdaptersNeverPublishWhatTheyLog() {
        let files = Self.productionFiles().filter {
            $0.path.contains("/OTLPReceiverAdapter/Sources/") || $0.path.hasSuffix("ClaudeSettingsTelemetryCheck.swift")
                || $0.path.hasSuffix("LayoutSharing.swift")
        }

        let offenders = Self.lines(matching: "privacy: .public", in: files)

        #expect(files.count >= 4)
        #expect(offenders.isEmpty, "public log interpolations: \(offenders)")
    }

    @Test(.enabled(if: isInRepository))
    func managedSettingsPathOnlyAsTheCheckDefault() {
        let offenders = Self.lines(matching: "ClaudeCode/managed-settings", in: Self.productionFiles())
            .filter { !$0.contains("ClaudeSettingsTelemetryCheck.swift") }

        #expect(offenders.isEmpty, "the managed settings path outside its check: \(offenders)")
    }
}
