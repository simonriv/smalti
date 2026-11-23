import Foundation
import SmaltiCore

/// The project around a directory, read from files only: the nearest `package.json` (its scripts), `Makefile` (its
/// targets) and git directory (current branch, local branches, whether the branch has an upstream).
///
/// It is asked on every keystroke, so a snapshot younger than `recheckInterval` is answered from memory; an older
/// one is recomputed only when a file it came from changed its modification date. At most `capacity`
/// directories are remembered, the least recently asked dropped first.
public actor FileProjectContext: ProjectContext {
    public static let recheckInterval: TimeInterval = 1
    public static let capacity = 64

    private struct Cached {
        let signature: [String: Date]
        let snapshot: ProjectSnapshot
        var checkedAt: Date
    }

    private let clock: @Sendable () -> Date
    private var cache: [String: Cached] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    public func snapshot(of directory: String) async -> ProjectSnapshot {
        let now = clock()
        if var cached = cache[directory] {
            if now.timeIntervalSince(cached.checkedAt) < Self.recheckInterval { return cached.snapshot }
            cached.checkedAt = now
            let sources = ProjectSources(directory: URL(filePath: directory))
            if sources.signature() == cached.signature {
                cache[directory] = cached
                return cached.snapshot
            }
        }
        let sources = ProjectSources(directory: URL(filePath: directory))
        let snapshot = sources.read()
        remember(Cached(signature: sources.signature(), snapshot: snapshot, checkedAt: now), for: directory)
        return snapshot
    }

    private func remember(_ entry: Cached, for directory: String) {
        cache[directory] = entry
        guard cache.count > Self.capacity, let oldest = cache.min(by: { $0.value.checkedAt < $1.value.checkedAt })
        else { return }
        cache[oldest.key] = nil
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
        let packed = Self.packedBranches(in: common.appending(path: "packed-refs"))
        return Array(Set(loose + packed)).sorted()
    }

    /// Branch names in `packed-refs`, scanning bytes: after a fetch it can hold hundreds of thousands of tags, and a
    /// regex per line takes seconds there.
    private static func packedBranches(in file: URL) -> [String] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let marker = Array(" refs/heads/".utf8)
        return data.split(separator: UInt8(ascii: "\n")).compactMap { line -> String? in
            guard let first = line.first, first != UInt8(ascii: "#"), first != UInt8(ascii: "^"),
                let start = line.firstRange(of: marker)
            else { return nil }
            return String(decoding: line[start.upperBound...], as: UTF8.self)
        }
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
