import Foundation
import Testing

/// F6 (C14, C15): adapters get the user's harness homes as parameters and never build the real ones themselves, and
/// only `SQLiteReader` talks to SQLite. Checked over every package's sources; fails naming file and line.
@Suite("Harness isolation guard")
struct HarnessIsolationGuardTests {
    static let realHomes = [#"".claude"#, #"".codex"#, #"".gemini"#, ".local/share/opencode", ".config/nvim"]
    /// The one place that resolves real homes from the launch arguments (as F3 does for Claude).
    static let homeResolvers = ["LaunchSettings.swift"]

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

    static func hits(in text: String, file: String, matching patterns: [String]) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .filter { _, line in !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { _, line in patterns.contains { line.contains($0) } }
            .map { index, _ in "\(file):\(index + 1)" }
    }

    @Test func guardFindsAPlantedRealHome() {
        let text = "let x = 1\nlet home = base.appending(path: \".codex\")\n// \".gemini\" in a comment"

        #expect(Self.hits(in: text, file: "X.swift", matching: Self.realHomes) == ["X.swift:2"])
    }

    @Test func adaptersNeverBuildRealHarnessHomes() throws {
        let found = sources()
        let hits = try found.filter { !Self.homeResolvers.contains($0.file.lastPathComponent) }.flatMap {
            Self.hits(
                in: try String(contentsOf: $0.file, encoding: .utf8),
                file: "\($0.package)/\($0.file.lastPathComponent)",
                matching: Self.realHomes)
        }

        #expect(found.count > 100, "the scan must see the packages' sources")
        #expect(hits.isEmpty, "real harness homes built at: \(hits.joined(separator: ", "))")
    }

    @Test func onlySQLiteReaderImportsSQLite() throws {
        let hits = try sources().filter { $0.package != "SQLiteReader" }.flatMap {
            Self.hits(
                in: try String(contentsOf: $0.file, encoding: .utf8),
                file: "\($0.package)/\($0.file.lastPathComponent)",
                matching: ["import SQLite3"])
        }

        #expect(hits.isEmpty, "SQLite imported at: \(hits.joined(separator: ", "))")
    }
}
