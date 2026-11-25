import Foundation
import SmaltiCore
import Testing

@testable import ClaudeTelemetryAdapter

@Suite("TranscriptLineTranslator")
struct TranscriptLineTranslatorTests {
    private let translator = TranscriptLineTranslator()

    private func translate(_ text: String, isSubagent: Bool = false) throws -> TranslatedLine {
        try translator.translate(Data(text.utf8), isSubagent: isSubagent)
    }

    @Test func linesWithoutMarkersAreNotParsed() throws {
        #expect(try translate(#"{"type":"attachment", broken"#).records.isEmpty)
    }

    @Test func brokenRelevantLineThrows() {
        #expect(throws: TranscriptLineTranslator.UnreadableLine.self) { try translate(#"{"type":"assistant", broken"#) }
    }

    @Test func unknownTypeSaysNothing() throws {
        #expect(try translate(#"{"type":"queue-operation","assistant":true}"#).records.isEmpty)
    }

    @Test func derivedFromNamesItsSources() throws {
        let line =
            #"{"type":"derived-from","sessionId":"fork","sessions":[{"type":"claude_code_session","id":"source","via":"fork"}]}"#

        #expect(try translate(line).derivedFrom == ["source"])
    }

    @Test func replyCarriesUsageToolsAndSession() throws {
        let line =
            #"{"type":"assistant","timestamp":"2026-11-18T15:00:00.250Z","sessionId":"s","cwd":"/w","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls","timeout":5}}],"usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":4,"cache_creation_input_tokens":11,"cache_creation":{"ephemeral_5m_input_tokens":5,"ephemeral_1h_input_tokens":6}}}}"#

        let records = try translate(line).records

        #expect(records.count == 3)
        guard case .assistantTurn(let turn) = records[1], case .toolStarted(let tool) = records[2] else {
            Issue.record("expected a turn and a tool start")
            return
        }
        #expect(turn.usage == TokenUsage(input: 2, output: 3, cacheRead: 4, cacheWrite5m: 5, cacheWrite1h: 6))
        #expect(tool.input == ["command": "ls"])
    }

    /// A Write's whole file must not end up in the index: tool inputs are kept short.
    @Test func longToolInputsAreTruncated() throws {
        let content = String(repeating: "x", count: 5_000)
        let line =
            #"{"type":"assistant","timestamp":"2026-11-18T15:00:00Z","sessionId":"s","message":{"id":"m1","model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/a.txt","content":"\#(content)"}}],"usage":{"output_tokens":1}}}"#

        let records = try translate(line).records

        guard case .toolStarted(let tool) = records.last else {
            Issue.record("expected a tool start")
            return
        }
        #expect(tool.input["content"]?.count == TranscriptLineTranslator.inputLimit)
        #expect(tool.input["file_path"] == "/a.txt")
    }

    @Test func subagentReplyIsMarkedAndGivesNoSessionInfo() throws {
        let line =
            #"{"type":"assistant","timestamp":"2026-11-18T15:00:00Z","sessionId":"s","cwd":"/w","message":{"id":"m1","model":"claude-haiku-5-5","content":[],"usage":{"output_tokens":1}}}"#

        let records = try translate(line, isSubagent: true).records

        guard case .assistantTurn(let turn) = records.first else {
            Issue.record("expected a turn")
            return
        }
        #expect(turn.isSubagent)
        #expect(records.count == 1)
    }
}

@Suite("TranscriptIndex")
struct TranscriptIndexTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "smalti-index-\(UUID())/index.json")

    /// F7.6: an index written by a newer Smalti is a cache this build cannot read: it starts empty and leaves it.
    @Test func newerIndexIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"version":2,"futuro":true}"#.utf8)
        try newer.write(to: file)

        let index = TranscriptIndex.load(from: file)
        try index.save(to: file)

        #expect(index.files.isEmpty)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test func currentIndexIsSaved() throws {
        var index = TranscriptIndex()
        index.files["/a"] = TranscriptIndex.FileEntry(
            inode: 1, size: 2, offset: 3, modified: Date(timeIntervalSince1970: 0), sessionID: "s", isSubagent: false)

        try index.save(to: file)

        #expect(TranscriptIndex.load(from: file).files["/a"]?.offset == 3)
    }

    @Test func sourcesReadAgainAreKeptOnce() {
        #expect(TranscriptIndex.FileEntry.merging(["s"], ["s", "t", "t"]) == ["s", "t"])
    }
}
