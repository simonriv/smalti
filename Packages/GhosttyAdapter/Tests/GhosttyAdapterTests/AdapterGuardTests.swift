import Foundation
import Testing

/// A8: Smalti never reads the user's Ghostty configuration.
@Suite("Adapter guard")
struct AdapterGuardTests {
    private let forbiddenCalls = [
        "ghostty_config_load_default_files", "ghostty_config_load_cli_args", "ghostty_config_load_recursive_files",
    ]

    @Test func adapterNeverLoadsUserGhosttyConfig() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/GhosttyAdapter")
        let files =
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []

        let hits = try files.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .filter { _, line in forbiddenCalls.contains { line.contains($0) } }
                .map { index, _ in "\(url.lastPathComponent):\(index + 1)" }
        }

        #expect(files.isEmpty == false)
        #expect(hits.isEmpty, "User Ghostty config loaded at: \(hits.joined(separator: ", "))")
    }
}
