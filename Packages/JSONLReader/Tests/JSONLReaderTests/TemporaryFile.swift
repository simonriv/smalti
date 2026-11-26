import Foundation

/// A file in a fresh temporary folder, removed when the test ends.
final class TemporaryFile {
    let folder: URL
    let url: URL

    init(_ contents: String = "") throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "jsonl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "t.jsonl")
        try Data(contents.utf8).write(to: url)
    }

    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}
