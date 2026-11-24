import Foundation
import SmaltiCore

/// `PromptFacts` from the repository's files, `git status` and the runtimes' executables (spec F5). The repository
/// root is given in the terms of the directory asked (a symlinked `$PWD` stays symlinked), so the prompt can show the
/// path from the root.
public actor FilePromptFacts: PromptFacts {
    public static let gitTimeout = Duration.milliseconds(300)
    public static let versionTimeout = Duration.seconds(1)
    private static let git = "/usr/bin/git"

    private let runner: any CommandRunner
    private var changesCache: [String: (signature: [String: Date], changes: GitChanges)] = [:]
    private var versions: [String: (date: Date?, version: String?)] = [:]

    public init(runner: any CommandRunner = SystemCommandRunner()) {
        self.runner = runner
    }

    public func facts(for query: PromptQuery) async -> PromptFactsResult {
        let directory = URL(filePath: query.directory)
        let repository = RepositoryFiles(around: directory)
        let changes: GitChanges? =
            if let repository { await changes(in: repository, directory: query.directory) } else { nil }
        return PromptFactsResult(
            repoRoot: repository?.root, branch: repository?.branch, changes: changes,
            runtime: await runtime(for: directory, paths: query.runtimePaths),
            kubeContext: KubeContext.current(in: query.kubeconfig))
    }

    private func changes(in repository: RepositoryFiles, directory: String) async -> GitChanges? {
        let signature = repository.signature()
        if let cached = changesCache[repository.root], cached.signature == signature { return cached.changes }
        let arguments = ["status", "--porcelain=v2", "--untracked-files=no"]
        guard let output = await runner.run(Self.git, arguments, in: directory, timeout: Self.gitTimeout) else {
            return nil
        }
        let changes = GitStatusReader.changes(in: output)
        changesCache[repository.root] = (signature, changes)
        return changes
    }

    private func runtime(for directory: URL, paths: [RuntimeKind: String]) async -> RuntimeVersion? {
        guard let kind = RuntimeVersions.kind(for: directory), let path = paths[kind] else { return nil }
        let date = modificationDate(of: path)
        if let cached = versions[path], cached.date == date, date != nil {
            return cached.version.map { RuntimeVersion(kind: kind, version: $0) }
        }
        let output = await runner.run(
            path, RuntimeVersions.arguments(for: kind), in: directory.path(percentEncoded: false),
            timeout: Self.versionTimeout)
        let version = output.flatMap(RuntimeVersions.majorMinor)
        versions[path] = (date, version)
        return version.map { RuntimeVersion(kind: kind, version: $0) }
    }

    private func modificationDate(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// The repository around a directory: its root, its branch (or short SHA when detached) and the files whose dates
/// say `git status` may have changed.
struct RepositoryFiles {
    let root: String
    private let git: GitDirectory

    init?(around directory: URL) {
        var current = directory.standardizedFileURL
        while true {
            let dotGit = current.appending(path: ".git")
            if FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false)),
                let git = GitDirectory(dotGit: dotGit)
            {
                root = current.path(percentEncoded: false).trimmingSlash
                self.git = git
                return
            }
            let parent = current.deletingLastPathComponent()
            if parent.path(percentEncoded: false) == current.path(percentEncoded: false) { return nil }
            current = parent
        }
    }

    var branch: String? {
        if let name = git.branch { return name }
        guard let head = try? String(contentsOf: git.head.appending(path: "HEAD"), encoding: .utf8) else { return nil }
        let sha = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.count >= 7 && sha.allSatisfy(\.isHexDigit) ? String(sha.prefix(7)) : nil
    }

    func signature() -> [String: Date] {
        [git.head.appending(path: "index"), git.head.appending(path: "HEAD")].reduce(into: [:]) { dates, file in
            let path = file.path(percentEncoded: false)
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? Int) ?? -1
            dates["\(path)#\(size)"] = attributes?[.modificationDate] as? Date
        }
    }
}

extension String {
    fileprivate var trimmingSlash: String { count > 1 && hasSuffix("/") ? String(dropLast()) : self }
}

/// `git status --porcelain=v2` lines: `1 XY …` and `2 XY …` (renames) count X ≠ `.` as staged and Y ≠ `.` as
/// modified; `u …` (unmerged) counts as modified.
enum GitStatusReader {
    static func changes(in output: String) -> GitChanges {
        var modified = 0
        var staged = 0
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2)
            guard let kind = fields.first else { continue }
            if kind == "u" {
                modified += 1
                continue
            }
            guard kind == "1" || kind == "2", fields.count > 1, fields[1].count == 2 else { continue }
            let codes = Array(fields[1])
            if codes[0] != "." { staged += 1 }
            if codes[1] != "." { modified += 1 }
        }
        return GitChanges(modified: modified, staged: staged)
    }
}

/// Which runtime a project uses, by its files (Node → Bun → Python → Go, a Bun lock beating `package.json`), and how
/// to read its version.
enum RuntimeVersions {
    static func kind(for directory: URL) -> RuntimeKind? {
        if has(["bun.lockb", "bun.lock"], from: directory) { return .bun }
        if has(["package.json"], from: directory) { return .node }
        if has(["pyproject.toml", "requirements.txt"], from: directory) { return .python }
        if has(["go.mod"], from: directory) { return .go }
        return nil
    }

    static func arguments(for kind: RuntimeKind) -> [String] {
        kind == .go ? ["version"] : ["--version"]
    }

    /// "v22.11.0" → "22.11"; "go version go1.24.2 …" → "1.24".
    static func majorMinor(_ output: String) -> String? {
        output.firstMatch(of: /(\d+)\.(\d+)/).map { "\($0.output.1).\($0.output.2)" }
    }

    /// The nearest directory upward that has one of `names`.
    private static func has(_ names: [String], from directory: URL) -> Bool {
        var current = directory.standardizedFileURL
        while true {
            for name in names
            where FileManager.default.fileExists(atPath: current.appending(path: name).path(percentEncoded: false)) {
                return true
            }
            if FileManager.default.fileExists(atPath: current.appending(path: ".git").path(percentEncoded: false)) {
                return false
            }
            let parent = current.deletingLastPathComponent()
            if parent.path(percentEncoded: false) == current.path(percentEncoded: false) { return false }
            current = parent
        }
    }
}

/// `current-context:` of a kubeconfig (`nil` path: `~/.kube/config`).
enum KubeContext {
    static func current(in kubeconfig: String?) -> String? {
        let path =
            kubeconfig
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kube/config")
            .path(percentEncoded: false)
        guard let text = try? String(contentsOf: URL(filePath: path), encoding: .utf8) else { return nil }
        return text.split(separator: "\n").lazy.compactMap { line -> String? in
            guard let match = line.firstMatch(of: /^current-context:\s*"?([^"\s]+)"?\s*$/) else { return nil }
            return String(match.output.1)
        }.first
    }
}
