import Foundation
import SmaltiCore

/// Entries as an adapter would translate them, built by hand (the adapters' own tests use the real fixtures).
enum TimelineFixtures {
    static let file = "/fx/s.jsonl"
    static let start = Date(timeIntervalSince1970: 1_795_000_000)

    static func excerpt(_ text: String, offset: UInt64, block: Int = 0, field: TextField = .text) -> ExcerptText {
        ExcerptText.make(
            full: text,
            location: TextLocation(
                file: file, inode: 1, offset: offset, length: text.utf8.count, block: block, field: field))
    }

    static func entry(_ kind: TranscriptEntry.Kind, scope: EntryScope = .main, second: Double = 0) -> TranscriptEntry {
        TranscriptEntry(kind: kind, scope: scope, at: start.addingTimeInterval(second))
    }

    static func prompt(_ text: String, at offset: UInt64, scope: EntryScope = .main) -> TranscriptEntry {
        entry(.prompt(excerpt(text, offset: offset)), scope: scope, second: Double(offset))
    }

    static func reply(_ text: String, at offset: UInt64, scope: EntryScope = .main) -> TranscriptEntry {
        entry(.reply(excerpt(text, offset: offset)), scope: scope, second: Double(offset))
    }

    static func call(
        _ id: String, _ name: String, _ arguments: [String: String], at offset: UInt64,
        scope: EntryScope = .main
    ) -> TranscriptEntry {
        let text = arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return entry(
            .toolCall(
                ToolCallEntry(
                    id: id, name: name, arguments: arguments, call: excerpt(text, offset: offset, field: .toolInput))),
            scope: scope, second: Double(offset))
    }

    static func result(
        _ id: String, _ output: String, at offset: UInt64, isError: Bool = false, exitCode: Int? = nil,
        scope: EntryScope = .main
    ) -> TranscriptEntry {
        entry(
            .toolResult(
                ToolResultEntry(
                    id: id, isError: isError, exitCode: exitCode, diff: nil,
                    output: excerpt(output, offset: offset, field: .toolOutput))),
            scope: scope, second: Double(offset))
    }

    /// F6's Claude fixture work-b, as entries: three turns, three tools, one failing.
    static let workB: [TranscriptEntry] = [
        prompt("fixture prompt B", at: 100),
        call("t1", "Bash", ["command": "ls"], at: 200),
        result("t1", "Exit code 127\n(eval):1: command not found: eza", at: 300, isError: true, exitCode: 127),
        call("t2", "Bash", ["command": "command ls | wc -l"], at: 400),
        result("t2", "       2", at: 500),
        reply("Hay 2 archivos en este directorio.", at: 600),
        prompt("fixture prompt B", at: 700),
        call("t3", "Read", ["file_path": "/w/uno.txt"], at: 800),
        result("t3", "<system-reminder>empty</system-reminder>", at: 900),
        reply("Sí, está vacío.", at: 1000),
        prompt("fixture prompt B", at: 1100),
        reply("listo", at: 1200),
    ]
}
