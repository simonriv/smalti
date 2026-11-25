import Foundation
import Testing

/// F6 (C14, C15): adapters get the user's harness homes as parameters and never build the real ones themselves, and
/// only `SQLiteReader` talks to SQLite. Checked over every package's sources; fails naming file and line.
@Suite("Harness isolation guard")
struct HarnessIsolationGuardTests {
    /// A real home as a path component (`".codex"`, `".gemini/…"`, `"/Users/s/.codex/…"`, `"~/.claude"`), not a word
    /// that merely contains it (`my.codex.plugin`).
    // The regex is a constant only read by the tests, so sharing it across concurrent tests is safe.
    nonisolated(unsafe) static let realHomes =
        #/(^|["/~])\.(claude|codex|gemini)(["/]|$)|\.local/share/opencode|\.config/nvim|Application Support/ClaudeCode/#
    /// The one place that resolves real homes from the launch arguments (as F3 does for Claude).
    static let homeResolvers = ["LaunchSettings.swift", "ClaudeSettingsTelemetryCheck.swift"]

    private var packages: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sources() -> [(package: String, file: URL)] {
        let files = FileManager.default
        let names = (try? files.contentsOfDirectory(atPath: packages.path)) ?? []
        return names.flatMap { package -> [(String, URL)] in
            let root = packages.appending(path: "\(package)/Sources")
            let found = files.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            return found.filter { $0.pathExtension == "swift" }.map { (package, $0) }
        }
    }

    static func hits(in text: String, file: String) -> [String] {
        lines(of: text).filter { _, line in line.contains(realHomes) }.map { index, _ in "\(file):\(index + 1)" }
    }

    static func hits(in text: String, file: String, containing needle: String) -> [String] {
        lines(of: text).filter { _, line in line.contains(needle) }.map { index, _ in "\(file):\(index + 1)" }
    }

    private static func lines(of text: String) -> [(offset: Int, element: Substring)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .filter { _, line in !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .map { ($0.offset, $0.element) }
    }

    @Test func guardFindsAPlantedRealHome() {
        let text = [
            "let x = 1", "let home = base.appending(path: \".codex\")", "// \".gemini\" in a comment",
            "let a = home.appending(path: \".gemini/antigravity-cli\")", "let b = \"/Users/s/.codex/sessions\"",
            "let c = \"~/.claude\"", "let d = \"my.codex.plugin\"",
            "let e = URL(filePath: \"/Library/Application Support/ClaudeCode/managed-settings.json\")",
        ].joined(separator: "\n")

        #expect(
            Self.hits(in: text, file: "X.swift") == ["X.swift:2", "X.swift:4", "X.swift:5", "X.swift:6", "X.swift:8"])
    }

    @Test func adaptersNeverBuildRealHarnessHomes() throws {
        let found = sources()
        let hits = try found.filter { !Self.homeResolvers.contains($0.file.lastPathComponent) }.flatMap {
            Self.hits(
                in: try String(contentsOf: $0.file, encoding: .utf8),
                file: "\($0.package)/\($0.file.lastPathComponent)")
        }

        #expect(found.count > 100, "the scan must see the packages' sources")
        #expect(hits.isEmpty, "real harness homes built at: \(hits.joined(separator: ", "))")
    }

    @Test func onlySQLiteReaderImportsSQLite() throws {
        let hits = try sources().filter { $0.package != "SQLiteReader" }.flatMap {
            Self.hits(
                in: try String(contentsOf: $0.file, encoding: .utf8),
                file: "\($0.package)/\($0.file.lastPathComponent)", containing: "import SQLite3")
        }

        #expect(hits.isEmpty, "SQLite imported at: \(hits.joined(separator: ", "))")
    }
}
