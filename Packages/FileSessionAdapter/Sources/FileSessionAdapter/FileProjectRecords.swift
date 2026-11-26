import Foundation
import SmaltiCore

/// `ProjectRecords` as `projects.json` in Smalti's state directory (F8.5), next to `session.json`: owner-only, written
/// atomically. A file that cannot be read, or that a newer Smalti wrote, lists nothing and is replaced on the next
/// write (projects are a convenience; approvals then ask again, which is the safe side).
public final class FileProjectRecords: ProjectRecords {
    static let fileName = "projects.json"
    static let formatVersion = 1

    private struct Stored: Codable {
        let version: Int
        let projects: [ProjectRecord]
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var file: URL { directory.appending(path: Self.fileName) }

    public func all() -> [ProjectRecord] {
        guard let data = FileManager.default.contents(atPath: file.path(percentEncoded: false)),
            let stored = try? Self.decoder.decode(Stored.self, from: data), stored.version == Self.formatVersion
        else { return [] }
        return stored.projects
    }

    public func replace(with records: [ProjectRecord]) throws(ProjectFileError) {
        let path = file.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try Self.encoder.encode(Stored(version: Self.formatVersion, projects: records))
            try AtomicFile.write(data, to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch let failure as SessionArchiveFailure {
            throw .unwritable(path: path, reason: failure.reason)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
