import Foundation
import SmaltiCore

/// Reads the sessions under `projects/<directory>/<id>.jsonl` from each transcript's head (directory, first prompt,
/// first timestamp) and tail (last timestamp), without reading whole transcripts. Subagent transcripts, which live
/// one level deeper, are not sessions. A transcript that cannot be read is skipped; if none names its directory, the
/// format changed.
struct ClaudeSessionList {
    static let headBytes = 256 * 1024
    static let tailBytes = 64 * 1024

    let root: URL
    let harness: HarnessID

    func sessions() throws(HarnessError) -> [HarnessSession] {
        let files = FileManager.default
        guard files.fileExists(atPath: root.path) else { throw .storeMissing(harness: harness, path: root.path) }
        let projects = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let transcripts = projects.flatMap { project in
            ((try? files.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
        let read = transcripts.compactMap(session)
        if !transcripts.isEmpty, read.isEmpty, transcripts.contains(where: hasRecords) {
            throw .unknownSchema(harness: harness, path: root.path, missing: "cwd")
        }
        return read
    }

    private func session(_ file: URL) -> HarnessSession? {
        guard let head = Self.records(Self.read(file, head: Self.headBytes)),
            let directory = head.lazy.compactMap({ $0["cwd"] as? String }).first,
            let created = head.lazy.compactMap(Self.timestamp).first
        else { return nil }
        let tail = Self.records(Self.read(file, tail: Self.tailBytes)) ?? []
        let updated = (tail + head).compactMap(Self.timestamp).max() ?? created
        let title = head.lazy.compactMap(Self.prompt).first ?? ""
        return HarnessSession(
            harness: harness, id: file.deletingPathExtension().lastPathComponent, directory: directory, title: title,
            createdAt: created, updatedAt: updated, detail: nil)
    }

    private func hasRecords(_ file: URL) -> Bool {
        !(Self.records(Self.read(file, head: Self.headBytes)) ?? []).isEmpty
    }

    /// The JSON objects among `text`'s lines; a cut first or last line is ignored.
    static func records(_ text: String?) -> [[String: Any]]? {
        guard let text else { return nil }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    static func read(_ file: URL, head bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func read(_ file: URL, tail bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file), let size = try? handle.seekToEnd() else {
            return nil
        }
        defer { try? handle.close() }
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return (try? handle.readToEnd()).map { String(decoding: $0, as: UTF8.self) }
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func timestamp(_ record: [String: Any]) -> Date? {
        guard let text = record["timestamp"] as? String else { return nil }
        return (try? fractional.parse(text)) ?? (try? plain.parse(text))
    }

    /// The first user prompt's text: a plain string, or the first text block.
    static func prompt(_ record: [String: Any]) -> String? {
        guard record["type"] as? String == "user", let message = record["message"] as? [String: Any] else {
            return nil
        }
        if let text = message["content"] as? String { return text }
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.first { $0["type"] as? String == "text" }?["text"] as? String
    }
}
