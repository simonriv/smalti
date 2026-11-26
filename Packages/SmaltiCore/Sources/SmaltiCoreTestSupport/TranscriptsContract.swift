import Foundation
import SmaltiCore
import Testing

/// One item of `scripts/timeline/timeline_oracle.py`: what the timeline must show for a transcript, apart from the
/// Swift adapters (spec F9, C1).
public struct OracleItem: Decodable, Equatable, Sendable {
    public let kind: String
    public let who: String
    public let scope: String
    public let text: String
}

public enum TimelineOracle {
    private struct Output: Decodable {
        let items: [OracleItem]
    }

    /// The repository's root, from this file's place (tests run inside the repository).
    public static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Runs the oracle with Python's isolated mode on `transcript` (and Claude's `subagents` folder).
    public static func items(harness: HarnessID, transcript: URL, subagents: URL? = nil) throws -> [OracleItem] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments =
            [
                "-I", repository.appending(path: "scripts/timeline/timeline_oracle.py").path, harness.rawValue,
                transcript.path,
            ] + (subagents.map { ["--subagents", $0.path] } ?? [])
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "the oracle failed on \(transcript.path)")
        return try JSONDecoder().decode(Output.self, from: data).items
    }
}

/// Shared contract of every `SessionTranscripts` (Claude Code and Codex): a session reads into the oracle's items, in
/// order, each text whole byte for byte, and every one of them is an item of the folded timeline.
public enum TranscriptsContract {
    public static func verify(
        _ transcripts: any SessionTranscripts, sessionID: String, oracle: [OracleItem],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let ref = try await transcripts.locate(sessionID: sessionID)
        let read = try await transcripts.read(ref, from: .start)
        let entries = read.entries.filter { if case .subagentLink = $0.kind { false } else { true } }
        let names = Dictionary(
            entries.compactMap { if case .toolCall(let call) = $0.kind { (call.id, call.name) } else { nil } },
            uniquingKeysWith: { first, _ in first })

        #expect(
            entries.map { signature($0, names: names) } == oracle.map { "\($0.kind) \(kindWho($0)) \($0.scope)" },
            sourceLocation: sourceLocation)
        for (entry, item) in zip(entries, oracle) {
            guard let location = location(of: entry) else { continue }
            let text = try await transcripts.fullText(at: location)
            #expect(
                Array(text.utf8) == Array(item.text.utf8), "\(item.kind) of \(item.who)", sourceLocation: sourceLocation
            )
        }
        let timeline = Timeline().appending(read.entries)
        for entry in entries {
            guard let id = itemID(of: entry) else { continue }
            #expect(timeline.item(id) != nil, "\(id.rawValue) is not in the timeline", sourceLocation: sourceLocation)
        }
    }

    private static func kindWho(_ item: OracleItem) -> String { item.kind == "image" ? "-" : item.who }

    private static func signature(_ entry: TranscriptEntry, names: [String: String]) -> String {
        let scope: String =
            switch entry.scope {
            case .main: "main"
            case .subagent(let agent): agent
            }
        let kindAndWho: String =
            switch entry.kind {
            case .prompt: "prompt user"
            case .reply: "reply agent"
            case .toolCall(let call): "call \(call.name)"
            case .toolResult(let result): "output \(names[result.id] ?? "?")"
            case .image: "image -"
            case .compaction: "compaction system"
            case .subagentLink: "link -"
            }
        return "\(kindAndWho) \(scope)"
    }

    private static func location(of entry: TranscriptEntry) -> TextLocation? {
        switch entry.kind {
        case .prompt(let text), .reply(let text): text.location
        case .toolCall(let call): call.call.location
        case .toolResult(let result): result.output.location
        case .image, .compaction, .subagentLink: nil
        }
    }

    private static func itemID(of entry: TranscriptEntry) -> TimelineItemID? {
        switch entry.kind {
        case .prompt(let text), .reply(let text): .at(text.location)
        case .toolCall(let call): .tool(call.id)
        case .toolResult(let result): .tool(result.id)
        case .image(let image): .at(image.location)
        case .compaction(let note): .at(note.location)
        case .subagentLink: nil
        }
    }
}
