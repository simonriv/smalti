@testable import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Read-only fixtures: F6's Claude home, F3's real transcripts (with the subagent) and F9's synthetic one.
enum TimelineFixturePaths {
    static let f6Projects = TimelineOracle.repository.appending(
        path: "Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/claude/home/.claude/projects")
    static let f3Projects = TimelineOracle.repository.appending(
        path: "Packages/ClaudeTelemetryAdapter/Tests/ClaudeTelemetryAdapterTests/Fixtures/real/projects")
    static let synthetic = TimelineOracle.repository.appending(
        path: "Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/timeline-synthetic")

    static func transcript(_ projects: URL, _ id: String) throws -> URL {
        let folders = try FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
        return try #require(
            folders.map { $0.appending(path: "\(id).jsonl") }.first {
                FileManager.default.fileExists(atPath: $0.path)
            })
    }
}

/// A projects folder of its own, with copies of transcripts a test may grow or rewrite.
final class ScratchProjects {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "claude-timeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func folder(_ name: String) throws -> URL {
        let folder = root.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("ClaudeTimeline")
struct ClaudeTimelineTests {
    private typealias P = TimelineFixturePaths

    @Test(arguments: [
        "401a63e1-c076-45fe-9f09-432da1c8cfa6", "0259e0a5-46f8-44f8-bc38-edfa7d1a0f2b",
        "7b1f7b2a-0c81-4aa0-8229-85de52add2e8",
    ])
    func f6TranscriptsMatchTheOracle(id: String) async throws {
        let oracle = try TimelineOracle.items(harness: .claude, transcript: try P.transcript(P.f6Projects, id))

        try await TranscriptsContract.verify(ClaudeTimeline(projectsRoot: P.f6Projects), sessionID: id, oracle: oracle)
    }

    @Test func f3TranscriptWithItsSubagentMatchesTheOracle() async throws {
        let id = "30e70a4d-2f90-4085-be04-73997b68c564"
        let main = try P.transcript(P.f3Projects, id)
        let oracle = try TimelineOracle.items(
            harness: .claude, transcript: main,
            subagents: main.deletingPathExtension().appending(path: "subagents"))

        try await TranscriptsContract.verify(ClaudeTimeline(projectsRoot: P.f3Projects), sessionID: id, oracle: oracle)
    }

    @Test func theSubagentNestsUnderItsAgentCall() async throws {
        let adapter = ClaudeTimeline(projectsRoot: P.f3Projects)
        let ref = try await adapter.locate(sessionID: "30e70a4d-2f90-4085-be04-73997b68c564")

        let timeline = Timeline().appending(try await adapter.read(ref, from: .start).entries)

        guard case .tool(let agent) = timeline.item(.tool("toolu_01BLBZCGQY5Q6NjV2pgQDzZr")) else {
            Issue.record("no Agent call")
            return
        }
        #expect(agent.children.count > 3)
        #expect(!timeline.turns.contains { $0.items.contains { $0.id == .agent("a83a716973cc0ff1d") } })
    }

    @Test func syntheticImagesMetaAndCompactionMatchTheOracle() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-fixture-work-s")
        try FileManager.default.copyItem(
            at: P.synthetic.appending(path: "image.jsonl"),
            to: folder.appending(path: "5e1f0000-0000-4000-8000-000000000001.jsonl"))
        let oracle = try TimelineOracle.items(
            harness: .claude, transcript: folder.appending(path: "5e1f0000-0000-4000-8000-000000000001.jsonl"))

        try await TranscriptsContract.verify(
            ClaudeTimeline(projectsRoot: projects.root), sessionID: "5e1f0000-0000-4000-8000-000000000001",
            oracle: oracle)
    }

    @Test func readingInTwoPiecesGivesTheSameTimeline() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        let source = try Data(contentsOf: try P.transcript(P.f6Projects, "7b1f7b2a-0c81-4aa0-8229-85de52add2e8"))
        let file = folder.appending(path: "s1.jsonl")
        let cut = source.count / 2
        try source.prefix(cut).write(to: file)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")

        let first = try await adapter.read(ref, from: .start)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: source.suffix(from: cut))
        try handle.close()
        let second = try await adapter.read(ref, from: first.cursor)
        let whole = try await adapter.read(ref, from: .start)

        #expect(!second.restarted)
        #expect(Timeline().appending(first.entries).appending(second.entries) == Timeline().appending(whole.entries))
    }

    @Test func aRewrittenFileRestarts() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        let file = folder.appending(path: "s1.jsonl")
        let source = try Data(contentsOf: try P.transcript(P.f6Projects, "7b1f7b2a-0c81-4aa0-8229-85de52add2e8"))
        try source.write(to: file)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")
        let first = try await adapter.read(ref, from: .start)

        try FileManager.default.removeItem(at: file)
        try source.prefix(source.count / 3).write(to: file)
        let again = try await adapter.read(ref, from: first.cursor)

        #expect(again.restarted)
        #expect(again.entries.count < first.entries.count)
    }

    @Test func anUnknownSessionIsMissing() async {
        await #expect(throws: TranscriptReadError.self) {
            try await ClaudeTimeline(projectsRoot: P.f6Projects).locate(sessionID: "nope")
        }
    }

    @Test func aChangedLineCannotBeCopied() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        let file = folder.appending(path: "s1.jsonl")
        try Data(contentsOf: try P.transcript(P.f6Projects, "7b1f7b2a-0c81-4aa0-8229-85de52add2e8")).write(to: file)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let read = try await adapter.read(try await adapter.locate(sessionID: "s1"), from: .start)
        guard case .prompt(let prompt) = read.entries.first?.kind else {
            Issue.record("expected a prompt first")
            return
        }

        try FileManager.default.removeItem(at: file)
        try Data("{}\n".utf8).write(to: file)

        await #expect(throws: TranscriptReadError.self) { try await adapter.fullText(at: prompt.location) }
    }

    @Test func changesTellWhenTheFileGrowsAndStopWhenCancelled() async throws {
        let projects = try ScratchProjects()
        let file = try projects.folder("-w").appending(path: "s1.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")

        let told = Task {
            for await _ in adapter.changes(of: ref) { return true }
            return false
        }
        try await Task.sleep(for: .milliseconds(50))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        let timeout = Task {
            try await Task.sleep(for: .seconds(2))
            told.cancel()
        }

        #expect(await told.value)
        timeout.cancel()
    }

    @Test func aSubagentBornWhileWatchingIsWatchedToo() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        try Data("{}\n".utf8).write(to: folder.appending(path: "s1.jsonl"))
        let subagents = folder.appending(path: "s1/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")
        let counter = Counter()
        let listening = Task {
            for await _ in adapter.changes(of: ref) { await counter.add() }
        }
        try await Task.sleep(for: .milliseconds(50))

        let agent = subagents.appending(path: "agent-a1.jsonl")
        try Data("{}\n".utf8).write(to: agent)
        try await Task.sleep(for: .milliseconds(400))
        let afterBirth = await counter.value
        let handle = try FileHandle(forWritingTo: agent)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await counter.value == afterBirth, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        listening.cancel()

        #expect(afterBirth >= 1)
        #expect(await counter.value > afterBirth)
    }

    /// Review 1 (M9): the first subagent of a session, whose folder did not exist when the timeline opened.
    @Test func aSubagentFolderBornWhileWatchingIsWatchedToo() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        let main = folder.appending(path: "s1.jsonl")
        try Data("{}\n".utf8).write(to: main)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")
        let counter = Counter()
        let listening = Task { for await _ in adapter.changes(of: ref) { await counter.add() } }
        try await Task.sleep(for: .milliseconds(50))

        let subagents = folder.appending(path: "s1/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let agent = subagents.appending(path: "agent-a1.jsonl")
        try Data("{}\n".utf8).write(to: agent)
        let mainHandle = try FileHandle(forWritingTo: main)
        try mainHandle.seekToEnd()
        try mainHandle.write(contentsOf: Data("{}\n".utf8))
        try mainHandle.close()
        try await Task.sleep(for: .milliseconds(400))
        let before = await counter.value
        let handle = try FileHandle(forWritingTo: agent)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await counter.value == before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        listening.cancel()

        #expect(await counter.value > before)
    }

    /// C6: when the timeline stops listening, no descriptor stays open on the session's files.
    @Test func stoppingToListenClosesEveryDescriptor() async throws {
        let projects = try ScratchProjects()
        let folder = try projects.folder("-w")
        let main = folder.appending(path: "s1.jsonl")
        try Data("{}\n".utf8).write(to: main)
        let subagents = folder.appending(path: "s1/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: subagents.appending(path: "agent-a1.jsonl"))
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")

        let listening = Task { for await _ in adapter.changes(of: ref) {} }
        try await Task.sleep(for: .milliseconds(100))
        let whileOpen = Descriptors.on(projects.root)
        listening.cancel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while Descriptors.on(projects.root) > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(whileOpen == 3)
        #expect(Descriptors.on(projects.root) == 0)
    }

    /// Review 1 (M8): a transcript that cannot be read is an error, not an empty timeline.
    @Test func anUnreadableTranscriptFails() async throws {
        let projects = try ScratchProjects()
        let file = try projects.folder("-w").appending(path: "s1.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let adapter = ClaudeTimeline(projectsRoot: projects.root)
        let ref = try await adapter.locate(sessionID: "s1")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        await #expect(throws: TranscriptReadError.self) { try await adapter.read(ref, from: .start) }
    }

    @Test func searchMeetsTheContract() async throws {
        for (id, root) in [
            ("7b1f7b2a-0c81-4aa0-8229-85de52add2e8", "/private/tmp/smalti-fx/claude/work-b"),
            ("401a63e1-c076-45fe-9f09-432da1c8cfa6", "/private/tmp/smalti-fx/claude/work-a"),
        ] {
            let oracle = try TimelineOracle.items(harness: .claude, transcript: try P.transcript(P.f6Projects, id))
            try await TranscriptsContract.verifySearch(
                ClaudeTimeline(projectsRoot: P.f6Projects), root: root, oracle: oracle)
        }
    }

    @Test func projectSessionsIncludeSubfoldersButNotSiblings() async throws {
        let projects = try ScratchProjects()
        let source = try String(
            contentsOf: try P.transcript(P.f6Projects, "401a63e1-c076-45fe-9f09-432da1c8cfa6"), encoding: .utf8)
        for (folder, cwd) in [("-p-app", "/p/app"), ("-p-app-web", "/p/app/web"), ("-p-app-v2", "/p/app-v2")] {
            let text = source.replacingOccurrences(of: "/private/tmp/smalti-fx/claude/work-a", with: cwd)
            try text.write(
                to: try projects.folder(folder).appending(path: "\(folder).jsonl"), atomically: true, encoding: .utf8)
        }
        let adapter = ClaudeTimeline(projectsRoot: projects.root)

        let sessions = try await adapter.sessions(under: "/p/app", limit: 10)

        #expect(Set(sessions.map(\.id)) == ["-p-app", "-p-app-web"])
        #expect(try await adapter.sessions(under: "/p/app", limit: 1).count == 1)
    }

    @Test func searchFindsTextAndConfirmsEachHit() async throws {
        let adapter = ClaudeTimeline(projectsRoot: P.f6Projects)
        var hits: [TranscriptHit] = []

        for try await hit in adapter.search(TimelineQuery("ARCHIVOS"), under: "/private/tmp/smalti-fx/claude/work-b") {
            hits.append(hit)
        }

        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.text.lowercased().contains("archivos") })
        #expect(hits.allSatisfy { $0.session.id == "7b1f7b2a-0c81-4aa0-8229-85de52add2e8" })
    }

    @Test func searchFindsAccentedTextWithoutAccents() async throws {
        let adapter = ClaudeTimeline(projectsRoot: P.f6Projects)
        var hits: [TranscriptHit] = []

        for try await hit in adapter.search(TimelineQuery("vacio"), under: "/private/tmp/smalti-fx/claude/work-b") {
            hits.append(hit)
        }

        #expect(hits.map(\.text) == ["Sí, está vacío."])
    }

    @Test func searchOutsideTheProjectFindsNothing() async throws {
        let adapter = ClaudeTimeline(projectsRoot: P.f6Projects)
        var count = 0

        for try await _ in adapter.search(TimelineQuery("hola"), under: "/elsewhere") { count += 1 }

        #expect(count == 0)
    }
}

actor Counter {
    private(set) var value = 0

    func add() { value += 1 }
}

/// Descriptors of this process open on anything under a folder.
enum Descriptors {
    static func on(_ folder: URL) -> Int {
        let prefix = folder.resolvingSymlinksInPath().path(percentEncoded: false)
        return (0..<Int32(getdtablesize())).filter { descriptor in
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) != -1 else { return false }
            return URL(filePath: String(cString: path)).resolvingSymlinksInPath().path(percentEncoded: false)
                .hasPrefix(prefix)
        }.count
    }
}
