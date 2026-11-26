import Foundation
import Testing

/// C11 (review 1, I6): the transcript readers only ever read. Runs inside the repository only (mutation testing copies
/// this package alone). The guard goes file by file: other files of the same adapters write their own settings.
@Suite("Transcript readers are read-only")
struct TranscriptReadOnlyGuardTests {
    private static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let isInRepository = FileManager.default.fileExists(
        atPath: repository.appending(path: "Packages/JSONLReader/Package.swift").path)

    static let readers = [
        "Packages/JSONLReader/Sources/JSONLReader",
        "Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/ClaudeTimeline.swift",
        "Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/ClaudeTimelineTranslator.swift",
        "Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/ClaudeSessionList.swift",
        "Packages/CodexHarnessAdapter/Sources/CodexHarnessAdapter/CodexTimeline.swift",
        "Packages/CodexHarnessAdapter/Sources/CodexHarnessAdapter/CodexTimelineTranslator.swift",
    ]
    static let writes = [
        "forWritingTo", "forUpdating", ".write(", "createFile", "removeItem", "moveItem", "copyItem", "replaceItem",
        "O_WRONLY", "O_RDWR", "O_CREAT", "truncate", "setAttributes", "createDirectory",
    ]

    private static func files(_ path: String) -> [URL] {
        let url = repository.appending(path: path)
        guard url.pathExtension != "swift" else { return [url] }
        return ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "swift" }
    }

    @Test(.enabled(if: isInRepository))
    func noReaderWritesTheDisk() throws {
        var found: [String] = []
        for file in Self.readers.flatMap(Self.files) {
            let lines = try String(contentsOf: file, encoding: .utf8).split(
                separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() where Self.writes.contains(where: line.contains) {
                found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        #expect(found.isEmpty, "a transcript reader writes: \(found)")
        #expect(Self.readers.flatMap(Self.files).count >= 8)
    }
}
