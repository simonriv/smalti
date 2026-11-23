import Foundation
import SmaltiCore

/// `AgentTranscripts` over Claude Code's `projects/` directory, read incrementally. Each call reads only the bytes
/// added since the last one, newest files first and within a time budget; `indexedSince` says from when on the
/// answer is complete. Everything runs on this actor, away from the main thread.
public actor ClaudeTranscripts: AgentTranscripts {
    private struct DiskFile {
        let url: URL
        let inode: UInt64
        let size: UInt64
        let modified: Date
        let sessionID: String
        let isSubagent: Bool
    }

    private let projects: URL
    private let indexFile: URL
    private let now: @Sendable () -> Date
    private let readBudget: Duration
    private let translator = TranscriptLineTranslator()
    private var index: TranscriptIndex?
    /// Lines that looked relevant but were not valid JSON, since this adapter started.
    public private(set) var skippedLines = 0

    public static let history: TimeInterval = 30 * 86_400

    public init(
        claudeHome: URL, indexFile: URL, now: @escaping @Sendable () -> Date, readBudget: Duration = .seconds(1)
    ) {
        projects = claudeHome.appending(path: "projects")
        self.indexFile = indexFile
        self.now = now
        self.readBudget = readBudget
    }

    public func activity(since: Date) async throws(TranscriptError) -> TranscriptActivity {
        let loaded = index ?? TranscriptIndex.load(from: indexFile)
        var current = loaded
        let windowStart = now().addingTimeInterval(-Self.history)
        let onDisk = try discover(after: windowStart)
        resetChangedFiles(onDisk, in: &current)
        let pending = onDisk.filter { ($0.size) > (current.files[$0.url.path]?.offset ?? 0) }
            .sorted { $0.modified > $1.modified }
        let unread = read(pending, into: &current)
        prune(&current, before: windowStart)
        index = current
        // Writing the index costs more than a refresh with nothing new; it is written only when it changed.
        if pending.count > unread.count || current.files != loaded.files { try? current.save(to: indexFile) }
        let indexedSince = unread.map(\.modified).max().map { max($0, windowStart) } ?? windowStart
        return TranscriptActivity(
            sessions: current.sessions.values.filter { ($0.lastActivity ?? .distantPast) >= since }
                .sorted { $0.sessionID < $1.sessionID },
            indexedSince: indexedSince)
    }

    // MARK: - Files

    private func discover(after windowStart: Date) throws(TranscriptError) -> [DiskFile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: projects.path(percentEncoded: false)) else { return [] }
        let projectDirectories: [URL]
        do {
            projectDirectories = try manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
        } catch {
            throw .unreadableRoot(path: projects.path(percentEncoded: false), reason: error.localizedDescription)
        }
        return projectDirectories.flatMap(transcripts(in:)).filter { $0.modified >= windowStart }
    }

    /// `<project>/<session>.jsonl` and `<project>/<session>/subagents/*.jsonl`.
    private func transcripts(in project: URL) -> [DiskFile] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
        let mains = entries.filter { $0.pathExtension == "jsonl" }.compactMap {
            file($0, session: $0.deletingPathExtension().lastPathComponent, isSubagent: false)
        }
        let subagents = entries.filter(\.hasDirectoryPath).flatMap { folder in
            let directory = folder.appending(path: "subagents")
            let files =
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "jsonl" }.compactMap {
                file($0, session: folder.lastPathComponent, isSubagent: true)
            }
        }
        return mains + subagents
    }

    private func file(_ url: URL, session: String, isSubagent: Bool) -> DiskFile? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
            let size = (attributes[.size] as? NSNumber)?.uint64Value,
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return DiskFile(
            url: url, inode: inode, size: size, modified: modified, sessionID: session, isSubagent: isSubagent)
    }

    /// A file that shrank or was replaced (another inode) is read again, with every other file of its session.
    private func resetChangedFiles(_ files: [DiskFile], in index: inout TranscriptIndex) {
        for file in files {
            guard let entry = index.files[file.url.path], entry.inode != file.inode || file.size < entry.offset else {
                continue
            }
            index.reset(file.sessionID)
            index.files[file.url.path]?.inode = file.inode
        }
    }

    // MARK: - Reading

    private struct ReadFile {
        let file: DiskFile
        let records: [TranscriptRecord]
        let derivedFrom: [String]
        let offset: UInt64
    }

    /// Reads newest first until the budget runs out (always at least one file); returns the files left unread.
    private func read(_ pending: [DiskFile], into index: inout TranscriptIndex) -> [DiskFile] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: readBudget)
        var done: [ReadFile] = []
        var remaining = pending[...]
        while let next = remaining.first, done.isEmpty || clock.now < deadline {
            remaining = remaining.dropFirst()
            done.append(read(next, from: index.files[next.url.path]?.offset ?? 0))
        }
        // A fork must not claim its source's copies first: its sources' new lines are read in this same pass.
        let sources = Set(
            done.flatMap(\.derivedFrom) + done.flatMap { index.files[$0.file.url.path]?.derivedFrom ?? [] })
        let pulled = remaining.filter { sources.contains($0.sessionID) }
        done += pulled.map { read($0, from: index.files[$0.url.path]?.offset ?? 0) }
        remaining = remaining.filter { !sources.contains($0.sessionID) }[...]
        let derived = { (read: ReadFile) in
            !read.derivedFrom.isEmpty || !(index.files[read.file.url.path]?.derivedFrom.isEmpty ?? true)
        }
        for item in MessageOwners.sourcesFirst(done, isDerived: derived) { fold(item, into: &index) }
        return Array(remaining)
    }

    private func read(_ file: DiskFile, from offset: UInt64) -> ReadFile {
        var records: [TranscriptRecord] = []
        var derivedFrom: [String] = []
        let end =
            (try? TranscriptLineReader.read(file.url, from: offset) { line in
                do {
                    let translated = try translator.translate(line, isSubagent: file.isSubagent)
                    records += translated.records
                    derivedFrom += translated.derivedFrom
                } catch {
                    skippedLines += 1
                }
            }) ?? offset
        return ReadFile(file: file, records: records, derivedFrom: derivedFrom, offset: end)
    }

    private func fold(_ item: ReadFile, into index: inout TranscriptIndex) {
        let session = item.file.sessionID
        let claimed = index.owners.claim(item.records, for: session)
        index.sessions[session] = (index.sessions[session] ?? SessionActivity(sessionID: session)).folding(claimed)
        var entry =
            index.files[item.file.url.path]
            ?? TranscriptIndex.FileEntry(
                inode: item.file.inode, size: item.file.size, offset: 0, modified: item.file.modified,
                sessionID: session, isSubagent: item.file.isSubagent)
        entry.inode = item.file.inode
        entry.size = item.file.size
        entry.offset = item.offset
        entry.modified = item.file.modified
        entry.derivedFrom += item.derivedFrom
        index.files[item.file.url.path] = entry
    }

    private func prune(_ index: inout TranscriptIndex, before windowStart: Date) {
        for (id, session) in index.sessions where (session.lastActivity ?? .distantPast) < windowStart {
            index.sessions[id] = nil
            index.owners.release(id)
        }
        index.files = index.files.filter { $0.value.modified >= windowStart }
    }
}
