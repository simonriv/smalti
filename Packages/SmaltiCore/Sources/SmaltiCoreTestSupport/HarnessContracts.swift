import Foundation
import SmaltiCore
import Testing

/// What a recorded fixture holds, written by `scripts/harnesses/fixture_expectations.py` (an oracle apart from the
/// Swift adapters).
public struct FixtureExpectations: Decodable, Sendable {
    public struct Session: Decodable, Sendable {
        public let id: String
        public let directory: String
        public let title: String
        public let createdAt: Date
    }

    public let harness: String
    public let sessions: [Session]

    public static func load(from fixture: URL) throws -> FixtureExpectations {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: fixture.appending(path: "expected.json")))
    }
}

/// How one harness's fixture is checked: where it lives, and the commands and process its adapter must produce.
public struct HarnessFixtureDescription: Sendable {
    public let harness: HarnessID
    /// `Fixtures/<harness>`, holding `home/` and `expected.json`.
    public let source: URL
    /// The fixed path the fixture was recorded under (`/private/tmp/smalti-fx/<harness>`).
    public let root: URL
    public let processName: String
    public let resume: @Sendable (String) -> String
    public let continueCommand: String
    public let fork: (@Sendable (String) -> String)?
    public let commandLine: @Sendable (String) -> [String]
    /// The file whose creation date is the session's (Antigravity), relative to the home.
    public let createdFile: (@Sendable (String) -> String)?

    public init(
        harness: HarnessID, source: URL, processName: String, resume: @escaping @Sendable (String) -> String,
        continueCommand: String, fork: (@Sendable (String) -> String)?,
        commandLine: @escaping @Sendable (String) -> [String], createdFile: (@Sendable (String) -> String)? = nil
    ) {
        self.harness = harness
        self.source = source
        self.root = URL(filePath: "/private/tmp/smalti-fx/\(harness.rawValue)")
        self.processName = processName
        self.resume = resume
        self.continueCommand = continueCommand
        self.fork = fork
        self.commandLine = commandLine
        self.createdFile = createdFile
    }
}

/// Copies a fixture's home to the fixed path it was recorded under, with its work directories. Harnesses keep those
/// paths inside binary blobs, so the copy goes back to them instead of rewriting them (spec F6, plan T1).
public enum FixtureHome {
    public static func materialize(_ fixture: HarnessFixtureDescription) throws -> URL {
        let files = FileManager.default
        try? files.removeItem(at: fixture.root)
        let home = fixture.root.appending(path: "home")
        try files.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try files.copyItem(at: fixture.source.appending(path: "home"), to: home)
        for work in ["work-a", "work-b"] {
            try files.createDirectory(at: fixture.root.appending(path: work), withIntermediateDirectories: true)
        }
        if let createdFile = fixture.createdFile {
            for session in try FixtureExpectations.load(from: fixture.source).sessions {
                let file = home.appending(path: createdFile(session.id))
                try files.setAttributes([.creationDate: session.createdAt], ofItemAtPath: file.path)
            }
        }
        return home
    }

    /// An empty home, for "the store is missing".
    public static func empty(_ fixture: HarnessFixtureDescription) throws -> URL {
        let home = fixture.root.appending(path: "empty-home")
        try? FileManager.default.removeItem(at: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}

/// The shared contract every `HarnessAdapter` passes on its real fixture (spec F6, C1).
public enum HarnessAdapterContract {
    public static func verify(
        fixture: HarnessFixtureDescription, make: (URL) -> any HarnessAdapter, breakSchema: (URL) throws -> Void
    ) async throws {
        let expected = try FixtureExpectations.load(from: fixture.source)
        let adapter = make(try FixtureHome.materialize(fixture))
        checkDetection(adapter, fixture)
        try await checkListing(adapter, expected)
        try await checkCapture(adapter, expected)
        checkCommands(adapter, fixture)
        await checkMissingStore(make(try FixtureHome.empty(fixture)))
        let broken = try FixtureHome.materialize(fixture)
        try breakSchema(broken)
        await checkUnknownSchema(make(broken))
        try? FileManager.default.removeItem(at: fixture.root)
    }

    static func checkDetection(_ adapter: any HarnessAdapter, _ fixture: HarnessFixtureDescription) {
        #expect(adapter.harness == fixture.harness)
        #expect(adapter.detect(ForegroundProcess(name: fixture.processName)), "detects its process")
        #expect(
            adapter.detect(ForegroundProcess(name: "node", commandLine: ["/opt/x/bin/\(fixture.processName)", "-c"])),
            "detects its process by the command line's executable")
        #expect(!adapter.detect(ForegroundProcess(name: "zsh")), "does not detect the shell")
    }

    static func checkListing(_ adapter: any HarnessAdapter, _ expected: FixtureExpectations) async throws {
        let all = try await adapter.listSessions(SessionQuery())
        #expect(all.map(\.id) == expected.sessions.map(\.id), "lists the fixture's sessions newest first")
        #expect(all.allSatisfy { $0.harness == adapter.harness })
        for (session, oracle) in zip(all, expected.sessions) {
            #expect(ResolvedPath.same(session.directory, oracle.directory), "directory of \(oracle.id)")
            #expect(session.title == oracle.title, "title of \(oracle.id)")
            #expect(abs(session.createdAt.timeIntervalSince(oracle.createdAt)) < 1, "creation of \(oracle.id)")
        }
        guard let first = expected.sessions.first else { return }
        let inDirectory = try await adapter.listSessions(SessionQuery(directory: first.directory))
        #expect(inDirectory.map(\.id) == expected.sessions.filter { $0.directory == first.directory }.map(\.id))
        let byText = try await adapter.listSessions(SessionQuery(text: first.title))
        #expect(byText.map(\.id).contains(first.id), "filters by text")
        let limited = try await adapter.listSessions(SessionQuery(limit: 1))
        #expect(limited.map(\.id) == [first.id], "honours the limit")
    }

    static func checkCapture(_ adapter: any HarnessAdapter, _ expected: FixtureExpectations) async throws {
        guard let newest = expected.sessions.max(by: { $0.createdAt < $1.createdAt }) else { return }
        let started = newest.createdAt.addingTimeInterval(-1)
        let window = CaptureWindow(directory: newest.directory, processStartedAt: started, excludedIDs: [])
        #expect(try await adapter.captureSessionId(in: window) == newest.id, "captures the session after the start")
        let late = CaptureWindow(
            directory: newest.directory, processStartedAt: newest.createdAt.addingTimeInterval(10), excludedIDs: [])
        #expect(try await adapter.captureSessionId(in: late) == nil, "ignores sessions created before the start")
        let elsewhere = CaptureWindow(
            directory: "/private/tmp/smalti-fx/nowhere", processStartedAt: started,
            excludedIDs: [])
        #expect(try await adapter.captureSessionId(in: elsewhere) == nil, "ignores other directories")
        let claimed = CaptureWindow(directory: newest.directory, processStartedAt: started, excludedIDs: [newest.id])
        #expect(try await adapter.captureSessionId(in: claimed) != newest.id, "skips ids other panes claimed")
    }

    static func checkCommands(_ adapter: any HarnessAdapter, _ fixture: HarnessFixtureDescription) {
        for id in ["01a210a3-2dac-78c0", "a'b c$d"] {
            let quoted = ShellWord.quoted(id)
            #expect(adapter.resumeCommand(sessionID: id) == fixture.resume(quoted), "resume command for \(id)")
            #expect(!adapter.resumeCommand(sessionID: id).contains("\n"), "the command is one line")
            #expect(adapter.forkCommand(sessionID: id) == fixture.fork?(quoted), "fork command for \(id)")
            let readBack = adapter.sessionID(fromCommandLine: fixture.commandLine(id))
            #expect(readBack == (ShellWord.isSafeID(id) ? id : nil), "reads \(id) back only when it is safe")
        }
        #expect(adapter.continueCommand() == fixture.continueCommand)
        #expect(adapter.sessionID(fromCommandLine: [fixture.processName]) == nil)
    }

    static func checkMissingStore(_ adapter: any HarnessAdapter) async {
        do {
            _ = try await adapter.listSessions(SessionQuery())
            Issue.record("a missing store must be an error")
        } catch {
            guard case .storeMissing = error else {
                Issue.record("expected storeMissing, got \(error)")
                return
            }
        }
    }

    static func checkUnknownSchema(_ adapter: any HarnessAdapter) async {
        do {
            _ = try await adapter.listSessions(SessionQuery())
            Issue.record("a changed schema must be an error")
        } catch {
            guard case .unknownSchema = error else {
                Issue.record("expected unknownSchema, got \(error)")
                return
            }
        }
    }
}
