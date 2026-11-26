import Foundation
import SmaltiCore

/// `ProjectPermissions` over a project's `.claude/settings.local.json` (spec F7.5): only `permissions.deny` changes;
/// every other key stays. A file Foundation cannot read as JSON (comments, trailing commas) is never rewritten.
public struct ClaudeProjectPermissions: ProjectPermissions {
    public init() {}

    public func deniedRules(in project: String) throws(ProjectPermissionsError) -> [String] {
        let settings = try read(Self.file(in: project))
        let permissions = settings["permissions"] as? [String: Any] ?? [:]
        guard let deny = permissions["deny"] else { return [] }
        guard let rules = deny as? [String] else {
            throw .denyNotAList(path: Self.path(in: project))
        }
        return rules
    }

    public func setDeniedRules(_ rules: [String], in project: String) throws(ProjectPermissionsError) {
        let file = Self.file(in: project)
        var settings = try read(file)
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        permissions["deny"] = rules
        settings["permissions"] = permissions
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try write(data + Data("\n".utf8), to: file)
        } catch {
            throw .unwritable(path: Self.path(in: project), reason: error.localizedDescription)
        }
    }

    /// Writes through a symlink (the link stays) and keeps the file's permissions (review 1).
    private func write(_ data: Data, to file: URL) throws {
        let target = file.resolvingSymlinksInPath()
        let path = target.path(percentEncoded: false)
        let permissions = try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]
        try data.write(to: target, options: .atomic)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        }
    }

    /// The project a folder belongs to for ⌘K (spec F7.5): the nearest folder with `.git`, or the folder itself.
    public static func projectRoot(containing directory: String) -> String {
        var current = URL(filePath: directory).standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appending(path: ".git").path(percentEncoded: false)) {
                let path = current.path(percentEncoded: false)
                return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path(percentEncoded: false) != current.path(percentEncoded: false) else { return directory }
            current = parent
        }
    }

    private static func file(in project: String) -> URL {
        URL(filePath: project).appending(path: ".claude/settings.local.json")
    }

    private static func path(in project: String) -> String {
        file(in: project).path(percentEncoded: false)
    }

    /// The settings as a dictionary; a missing file is empty.
    private func read(_ file: URL) throws(ProjectPermissionsError) -> [String: Any] {
        let path = file.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        do {
            let data = try Data(contentsOf: file)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProjectPermissionsError.notAnObject(path: path)
            }
            return object
        } catch let error as ProjectPermissionsError {
            throw error
        } catch {
            throw .unreadable(path: path, reason: "JSON inválido")
        }
    }
}
