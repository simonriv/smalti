import Foundation
import SmaltiCore

@testable import ClaudeTelemetryAdapter

/// A temporary Claude home for one test: `projects/` with copied or written transcripts, and an index file beside.
final class TranscriptHome {
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
    /// 2026-11-23 12:00 UTC: after every fixture's timestamps, within 30 days of them.
    static let now = Date(timeIntervalSince1970: 1_795_435_200)

    let root: URL
    var projects: URL { root.appending(path: "projects") }
    var indexFile: URL { root.appending(path: "state/observatory/index.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "claude-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func transcripts(budget: Duration = .seconds(60)) -> ClaudeTranscripts {
        ClaudeTranscripts(claudeHome: root, indexFile: indexFile, now: { TranscriptHome.now }, readBudget: budget)
    }

    func copyRealFixtures() throws {
        let source = Self.fixtures.appending(path: "real/projects")
        for project in try FileManager.default.contentsOfDirectory(atPath: source.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: source.appending(path: project), to: projects.appending(path: project))
        }
    }

    /// Copies a synthetic fixture as `<project>/<session>.jsonl` and returns its URL.
    @discardableResult
    func copySynthetic(_ name: String, session: String = "s", project: String = "-fixture-work-x") throws -> URL {
        let target = file(session: session, project: project)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtures.appending(path: "synthetic/\(name)"), to: target)
        return target
    }

    func file(session: String, project: String = "-fixture-work-x") -> URL {
        projects.appending(path: "\(project)/\(session).jsonl")
    }

    func write(_ lines: [String], session: String = "s", project: String = "-fixture-work-x") throws {
        let target = file(session: session, project: project)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: target)
    }

    func append(_ text: String, session: String = "s", project: String = "-fixture-work-x") throws {
        let handle = try FileHandle(forWritingTo: file(session: session, project: project))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    static func reply(_ id: String, output: Int = 100, at: String = "2026-11-18T15:00:00Z") -> String {
        #"{"type":"assistant","timestamp":"\#(at)","sessionId":"s","cwd":"/fixture/work/x","message":{"id":"\#(id)","model":"claude-haiku-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":\#(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
    }
}

extension SessionActivity {
    var total: TokenUsage { buckets.values.flatMap(\.usageByModel.values).reduce(.zero, +) }
}
