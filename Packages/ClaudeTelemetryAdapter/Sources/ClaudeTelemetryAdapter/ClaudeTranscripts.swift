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
    /// Reads that stopped halfway (the file vanished or became unreadable); they resume from where they stopped.
    public private(set) var readFailures = 0
    /// Index writes that failed; the index stays in memory and the next change tries again.
    public private(set) var indexWriteFailures = 0
    /// Index writes done; with agents working, changes come every few seconds and are written every 30 s at most.
    public private(set) var indexWrites = 0
    private var hasUnsavedChanges = false
    private var lastWrite: Date?

    public static let writeInterval: TimeInterval = 30

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
        if pending.count > unread.count || current.files != loaded.files { hasUnsavedChanges = true }
        saveIfDue()
        let indexedSince = unread.map(\.modified).max().map { max($0, windowStart) } ?? windowStart
        return TranscriptActivity(
            sessions: current.sessions.values.filter { ($0.lastActivity ?? .distantPast) >= since }
                .sorted { $0.sessionID < $1.sessionID },
            indexedSince: indexedSince,
            health: TranscriptHealth(
                skippedLines: skippedLines, readFailures: readFailures, indexWriteFailures: indexWriteFailures))
    }

    /// Writes what is still unsaved (on quit); otherwise a restart would reread up to 30 s of lines.
    public func persistIndex() {
        guard hasUnsavedChanges, let index else { return }
        save(index)
    }

    private func saveIfDue() {
        guard hasUnsavedChanges, let index else { return }
        if let lastWrite, now().timeIntervalSince(lastWrite) < Self.writeInterval { return }
        save(index)
    }

    private func save(_ index: TranscriptIndex) {
        lastWrite = now()
        do {
            if try index.save(to: indexFile) { indexWrites += 1 }
            hasUnsavedChanges = false
        } catch {
            indexWriteFailures += 1
        }
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
        var remaining = pending
        while let next = remaining.first, done.isEmpty || clock.now < deadline {
            remaining.removeFirst()
            done.append(read(next, from: index.files[next.url.path]?.offset ?? 0))
        }
        // A fork must not claim its sources' copies first: every source up its chain is read in this same pass.
        var sources = self.sources(of: done, in: index)
        while let position = remaining.firstIndex(where: { sources.contains($0.sessionID) }) {
            let source = remaining.remove(at: position)
            done.append(read(source, from: index.files[source.url.path]?.offset ?? 0))
            sources = self.sources(of: done, in: index)
        }
        let ordered = MessageOwners.sourcesFirst(
            done, session: \.file.sessionID, sources: { self.sources(of: [$0], in: index).sorted() })
        for item in ordered { fold(item, into: &index) }
        return remaining
    }

    /// The sessions the read files were forked from, from this pass and from what the index remembers.
    private func sources(of files: [ReadFile], in index: TranscriptIndex) -> Set<String> {
        let remembered = files.flatMap { file in
            index.files.values.filter { $0.sessionID == file.file.sessionID }.flatMap(\.derivedFrom)
        }
        return Set(files.flatMap(\.derivedFrom) + remembered)
    }

    private func read(_ file: DiskFile, from offset: UInt64) -> ReadFile {
        var records: [TranscriptRecord] = []
        var derivedFrom: [String] = []
        let outcome = TranscriptLineReader.read(file.url, from: offset) { line in
            // JSONSerialization autoreleases what it builds, and an actor's executor drains no pool between lines:
            // without one per line, a first read of 30 days keeps every parsed line alive until it ends.
            autoreleasepool {
                do {
                    let translated = try translator.translate(line, isSubagent: file.isSubagent)
                    records += translated.records
                    derivedFrom += translated.derivedFrom
                } catch {
                    skippedLines += 1
                }
            }
        }
        if outcome.failure != nil { readFailures += 1 }
        return ReadFile(file: file, records: records, derivedFrom: derivedFrom, offset: outcome.offset)
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
        entry.derivedFrom = TranscriptIndex.FileEntry.merging(entry.derivedFrom, item.derivedFrom)
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
