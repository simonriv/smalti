import Foundation
import SmaltiCore

/// The project around a directory, read from files only: the nearest `package.json` (its scripts), `Makefile` (its
/// targets) and git directory (current branch, local branches, whether the branch has an upstream). Snapshots
/// are cached per directory and recomputed when any file they came from changes its modification date.
public actor FileProjectContext: ProjectContext {
    private struct Cached {
        let signature: [String: Date]
        let snapshot: ProjectSnapshot
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    public func snapshot(of directory: String) async -> ProjectSnapshot {
        let sources = ProjectSources(directory: URL(filePath: directory))
        let signature = sources.signature()
        if let cached = cache[directory], cached.signature == signature { return cached.snapshot }
        let snapshot = sources.read()
        cache[directory] = Cached(signature: signature, snapshot: snapshot)
        return snapshot
    }
}

/// Where the project files for one directory are, searching upward from it.
struct ProjectSources {
    let packageJSON: URL?
    let makefile: URL?
    let git: GitDirectory?

    init(directory: URL) {
        packageJSON = Self.nearest("package.json", from: directory)
        makefile = Self.nearest("Makefile", from: directory)
        git = Self.nearest(".git", from: directory).flatMap(GitDirectory.init(dotGit:))
    }

    func read() -> ProjectSnapshot {
        ProjectSnapshot(
            scripts: packageJSON.map(Self.scripts(in:)) ?? [], makeTargets: makefile.map(Self.targets(in:)) ?? [],
            branch: git?.branch, branches: git?.branches ?? [], hasUpstream: git?.hasUpstream ?? false)
    }

    /// Modification dates of every file the snapshot reads; a change in any of them invalidates the cache.
    func signature() -> [String: Date] {
        let files = [packageJSON, makefile] + (git?.watchedFiles ?? [])
        return files.compactMap { $0 }.reduce(into: [:]) { dates, file in
            let path = file.path(percentEncoded: false)
            dates[path] = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        }
    }

    private static func nearest(_ name: String, from directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let candidate = current.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
            let parent = current.deletingLastPathComponent()
            if parent.path(percentEncoded: false) == current.path(percentEncoded: false) { return nil }
            current = parent
        }
    }

    private static func scripts(in file: URL) -> [String] {
        guard let data = try? Data(contentsOf: file),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = object["scripts"] as? [String: Any]
        else { return [] }
        return scripts.keys.sorted()
    }

    /// `name:` at the start of a line (letters, digits, `_`, `.`, `-`), without targets that start with `.`
    /// (`.PHONY`) and without variable assignments (`VAR := 1`).
    private static func targets(in file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: /^([A-Za-z0-9_][A-Za-z0-9_.-]*):(?!=)/) else { return nil }
            return String(match.output.1)
        }
    }
}

/// A repository's git directory, following a worktree's `gitdir:` file and its `commondir`.
struct GitDirectory {
    let head: URL
    let common: URL

    init?(dotGit: URL) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isFolder)
        else { return nil }
        if isFolder.boolValue {
            head = dotGit
            common = dotGit
            return
        }
        guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
            let path = pointer.split(separator: "\n").first?.firstMatch(of: /^gitdir:\s*(.+)$/)?.output.1
        else { return nil }
        let gitdir = Self.resolve(String(path), from: dotGit.deletingLastPathComponent())
        let commondir = (try? String(contentsOf: gitdir.appending(path: "commondir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        head = gitdir
        common = commondir.map { Self.resolve($0, from: gitdir) } ?? gitdir
    }

    /// An absolute path as is; a relative one from `base` (git writes both forms).
    private static func resolve(_ path: String, from base: URL) -> URL {
        (path.hasPrefix("/") ? URL(filePath: path) : base.appending(path: path)).standardizedFileURL
    }

    var branch: String? {
        guard let text = try? String(contentsOf: head.appending(path: "HEAD"), encoding: .utf8) else { return nil }
        return text.firstMatch(of: /^ref: refs\/heads\/(.+?)\s*$/).map { String($0.output.1) }
    }

    var branches: [String] {
        let refs = common.appending(path: "refs/heads")
        let loose = (FileManager.default.subpaths(atPath: refs.path(percentEncoded: false)) ?? []).filter { name in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(
                atPath: refs.appending(path: name).path(percentEncoded: false), isDirectory: &isFolder)
            return !isFolder.boolValue
        }
        let packedText = (try? String(contentsOf: common.appending(path: "packed-refs"), encoding: .utf8)) ?? ""
        let packed = packedText.split(separator: "\n").compactMap { line in
            line.firstMatch(of: /^[0-9a-f]+ refs\/heads\/(.+)$/).map { String($0.output.1) }
        }
        return Array(Set(loose + packed)).sorted()
    }

    /// `[branch "<current>"]` with a `remote` key in the repository's config.
    var hasUpstream: Bool {
        guard let branch, let config = try? String(contentsOf: common.appending(path: "config"), encoding: .utf8)
        else { return false }
        var isInSection = false
        for line in config.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                isInSection = line == "[branch \"\(branch)\"]"
            } else if isInSection && line.hasPrefix("remote") && line.contains("=") {
                return true
            }
        }
        return false
    }

    var watchedFiles: [URL] {
        [
            head.appending(path: "HEAD"), common.appending(path: "packed-refs"), common.appending(path: "refs/heads"),
            common.appending(path: "config"),
        ]
    }
}
