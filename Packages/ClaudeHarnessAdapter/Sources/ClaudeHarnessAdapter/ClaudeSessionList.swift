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

    /// The `newest` transcripts by modification time, read; a whole-machine listing never opens them all.
    func sessions(newest limit: Int) throws(HarnessError) -> [HarnessSession] {
        let transcripts = try allTranscripts()
        let newest = transcripts.map { ($0, Self.modified($0)) }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        return try read(Array(newest), checking: transcripts)
    }

    /// The transcripts of `directory`'s project folder born since `born`.
    func sessions(inProjectOf directory: String, bornSince born: Date) throws(HarnessError) -> [HarnessSession] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw .storeMissing(harness: harness, path: root.path)
        }
        guard let folder = projectFolderURL(for: directory) else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" && Self.born($0) >= born }
        return files.compactMap(session)
    }

    /// F9: the sessions whose directory is `root` or under it, newest first, with their transcript. Folders are picked
    /// by their encoded name (`root`'s, or it followed by `-`) and confirmed by the `cwd` the transcript names.
    func sessions(under root: String, limit: Int) throws(HarnessError) -> [(session: HarnessSession, file: URL)] {
        let files = FileManager.default
        guard files.fileExists(atPath: self.root.path) else {
            throw .storeMissing(harness: harness, path: self.root.path)
        }
        let name = Self.projectFolder(for: root)
        let folders = ((try? files.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent == name || $0.lastPathComponent.hasPrefix(name + "-") }
        let transcripts = folders.flatMap { folder in
            ((try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
        var found: [(session: HarnessSession, file: URL)] = []
        for file in transcripts.map({ ($0, Self.modified($0)) }).sorted(by: { $0.1 > $1.1 }).map(\.0) {
            guard found.count < limit else { break }
            guard let session = autoreleasepool(invoking: { session(file) }),
                session.directory == root || session.directory.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            else { continue }
            found.append((session, file))
        }
        return found
    }

    /// Claude Code (2.1) names a project's folder `cwd.replace(/[^a-zA-Z0-9]/g, "-")`: every UTF-16 unit that is not
    /// an ASCII letter or digit becomes `-`.
    static func projectFolder(for directory: String) -> String {
        String(
            directory.utf16.map { unit in
                let scalar = Unicode.Scalar(unit).map(Character.init)
                return scalar.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" } ?? "-"
            })
    }

    /// Past 200 characters Claude cuts the name and adds a hash of its own: the one folder with that prefix.
    static let longNameLimit = 200

    private func projectFolderURL(for directory: String) -> URL? {
        let name = Self.projectFolder(for: directory)
        guard name.count > Self.longNameLimit else { return root.appending(path: name) }
        let prefix = String(name.prefix(Self.longNameLimit)) + "-"
        let matches = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter {
            $0.hasPrefix(prefix)
        }
        return matches.count == 1 ? root.appending(path: matches[0]) : nil
    }

    private func allTranscripts() throws(HarnessError) -> [URL] {
        let files = FileManager.default
        guard files.fileExists(atPath: root.path) else { throw .storeMissing(harness: harness, path: root.path) }
        let projects = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return projects.flatMap { project in
            ((try? files.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    private func read(_ files: [URL], checking all: [URL]) throws(HarnessError) -> [HarnessSession] {
        let read = files.compactMap { file in autoreleasepool { session(file) } }
        if !all.isEmpty, read.isEmpty, all.contains(where: hasRecords) {
            throw .unknownSchema(harness: harness, path: root.path, missing: "cwd")
        }
        return read
    }

    private static func modified(_ file: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date ?? .distantPast
    }

    private static func born(_ file: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.creationDate] as? Date ?? .distantPast
    }

    func session(_ file: URL) -> HarnessSession? {
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
