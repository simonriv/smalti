import Foundation
import SmaltiCore

/// Resumes with `fake --resume <id>`. Without a home it poses as Claude for the restore tests; with one it keeps its
/// sessions in `<home>/fake-sessions.json`, so the shared contract runs without any harness installed.
public struct FakeHarnessAdapter: HarnessAdapter {
    public static let binary = "fake"
    public static let storeName = "fake-sessions.json"
    public static let fixtureHarness = HarnessID(rawValue: "fake")

    public let harness: HarnessID
    private let home: URL?

    public init() {
        self.harness = .claude
        self.home = nil
    }

    public init(home: URL) {
        self.harness = Self.fixtureHarness
        self.home = home
    }

    public var displayName: String { "Fake" }

    public func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, [Self.binary]) }

    public func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
        guard let home else { return [] }
        let store = home.appending(path: Self.storeName)
        guard let data = try? Data(contentsOf: store) else {
            throw .storeMissing(harness: harness, path: store.path)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let rows = try? decoder.decode([Row].self, from: data) else {
            throw .unknownSchema(harness: harness, path: store.path, missing: "directory")
        }
        let sessions = rows.map {
            HarnessSession(
                harness: harness, id: $0.id, directory: $0.directory, title: $0.title, createdAt: $0.createdAt,
                updatedAt: $0.updatedAt, detail: nil)
        }
        return SessionCatalog.merge([.success(sessions)], query: query).sessions
    }

    public func resumeCommand(sessionID: String) -> String {
        "\(Self.binary) --resume \(ShellWord.quoted(sessionID))"
    }

    public func continueCommand() -> String { "\(Self.binary) --continue" }

    public func forkCommand(sessionID: String) -> String? {
        "\(Self.binary) --fork \(ShellWord.quoted(sessionID))"
    }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, ProcessNames.matches(ForegroundProcess(name: first), [Self.binary]) else {
            return nil
        }
        return ProcessNames.value(after: ["--resume"], in: arguments)
    }

    private struct Row: Codable {
        let id: String
        let directory: String
        let title: String
        let createdAt: Date
        let updatedAt: Date
    }
}

/// A synthetic fixture for `FakeHarnessAdapter`, with the same layout as a recorded one.
public enum FakeHarnessFixture {
    public struct Made {
        public let description: HarnessFixtureDescription
    }

    public static func make() throws -> Made {
        let source = FileManager.default.temporaryDirectory.appending(path: "fake-fixture-\(UUID().uuidString)")
        let home = source.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let root = "/private/tmp/smalti-fx/fake"
        let sessions: [[String: String]] = [
            [
                "id": "s-b", "directory": "\(root)/work-b", "title": "Fixture B", "createdAt": "2026-11-25T02:58:09Z",
                "updatedAt": "2026-11-25T02:58:20Z",
            ],
            [
                "id": "s-a", "directory": "\(root)/work-a", "title": "Fixture A", "createdAt": "2026-11-25T02:57:39Z",
                "updatedAt": "2026-11-25T02:57:50Z",
            ],
        ]
        try JSONSerialization.data(withJSONObject: sessions).write(
            to: home.appending(path: FakeHarnessAdapter.storeName))
        let expected: [String: Any] = [
            "harness": "fake",
            "sessions": sessions.map {
                [
                    "id": $0["id"], "directory": $0["directory"], "title": $0["title"],
                    "createdAt": $0["createdAt"],
                ]
            },
        ]
        try JSONSerialization.data(withJSONObject: expected).write(to: source.appending(path: "expected.json"))
        let description = HarnessFixtureDescription(
            harness: FakeHarnessAdapter.fixtureHarness, source: source, processName: FakeHarnessAdapter.binary,
            resume: { "fake --resume \($0)" }, continueCommand: "fake --continue", fork: { "fake --fork \($0)" },
            commandLine: { ["fake", "--resume", $0] })
        return Made(description: description)
    }
}
