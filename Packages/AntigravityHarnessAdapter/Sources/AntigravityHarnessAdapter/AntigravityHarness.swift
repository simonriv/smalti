import Foundation
import SQLiteReader
import SmaltiCore

/// Antigravity (`agy`) as a harness. Its conversations are summarised in
/// `~/.gemini/antigravity-cli/conversation_summaries.db`; a conversation's creation is its file's birth time,
/// `conversations/<id>.db`, which the summary does not keep (spec F6, spike T1).
public struct AntigravityHarness: HarnessAdapter {
    static let requiredColumns = ["conversation_id", "title", "workspace_uris", "last_modified_time"]

    public let harness = HarnessID.antigravity
    private let root: URL

    /// `root` is `~/.gemini/antigravity-cli`, resolved by the composition root.
    public init(root: URL) {
        self.root = root
    }

    private var store: URL { root.appending(path: "conversation_summaries.db") }

    public func detect(_ process: ForegroundProcess) -> Bool {
        ProcessNames.matches(process, ["antigravity", "agy"])
    }

    public func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
        guard FileManager.default.fileExists(atPath: store.path) else {
            throw .storeMissing(harness: harness, path: store.path)
        }
        let reader = SQLiteReader(url: store)
        do {
            let columns = try reader.columns(of: "conversation_summaries")
            if let missing = Self.requiredColumns.first(where: { !columns.contains($0) }) {
                throw HarnessError.unknownSchema(harness: harness, path: store.path, missing: missing)
            }
            let preview = columns.contains("preview") ? "preview" : "null"
            let rows = try reader.rows(
                "select conversation_id, title, \(preview), workspace_uris, last_modified_time "
                    + "from conversation_summaries order by last_modified_time desc")
            return SessionCatalog.merge([.success(rows.compactMap(session))], query: query).sessions
        } catch let error as HarnessError {
            throw error
        } catch {
            throw .unreadable(harness: harness, path: store.path, reason: String(describing: error))
        }
    }

    private func session(_ row: SQLiteRow) -> HarnessSession? {
        guard let id = row[text: 0], let directory = row[text: 3].flatMap(Self.directory),
            let updated = row[text: 4].flatMap(Self.timestamp)
        else { return nil }
        let title = row[text: 1].flatMap { $0.isEmpty ? nil : $0 } ?? row[text: 2] ?? ""
        // Without its conversation file the creation is unknown: never newer than a process start (review 1, M2).
        return HarnessSession(
            harness: harness, id: id, directory: directory, title: title, createdAt: born(id) ?? .distantPast,
            updatedAt: updated, detail: nil)
    }

    private func born(_ id: String) -> Date? {
        let file = root.appending(path: "conversations/\(id).db")
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.creationDate] as? Date
    }

    /// The first `file://` workspace, decoded (`file:///tmp/a%20b` → `/tmp/a b`).
    static func directory(_ uris: String) -> String? {
        guard let list = (try? JSONSerialization.jsonObject(with: Data(uris.utf8))) as? [String],
            let file = list.first(where: { $0.hasPrefix("file://") }), let url = URL(string: file), url.isFileURL
        else { return nil }
        return url.path(percentEncoded: false)
    }

    /// `2026-11-25 02:58:49.003794+00:00` (any fraction, `T` or space, `Z` or an offset).
    public static func timestamp(_ text: String) -> Date? {
        let pattern = /^(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d):(\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)$/
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let (year, month, day) = (Int(match.1), Int(match.2), Int(match.3))
        let (hour, minute, second) = (Int(match.4), Int(match.5), Int(match.6))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let base = calendar.date(from: components) else { return nil }
        let fraction = match.7.flatMap { Double("0" + $0) } ?? 0
        return base.addingTimeInterval(fraction - offsetSeconds(String(match.8)))
    }

    private static func offsetSeconds(_ zone: String) -> TimeInterval {
        guard zone != "Z" else { return 0 }
        let sign: TimeInterval = zone.hasPrefix("-") ? -1 : 1
        let parts = zone.dropFirst().split(separator: ":").compactMap { TimeInterval($0) }
        return sign * ((parts.first ?? 0) * 3600 + (parts.last ?? 0) * 60)
    }

    public func resumeCommand(sessionID: String) -> String {
        "agy --conversation \(ShellWord.quoted(sessionID))"
    }

    public func continueCommand() -> String { "agy -c" }

    /// Antigravity has no fork.
    public func forkCommand(sessionID: String) -> String? { nil }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, detect(ForegroundProcess(name: first)) else { return nil }
        return ProcessNames.value(after: ["--conversation"], in: arguments)
    }
}
