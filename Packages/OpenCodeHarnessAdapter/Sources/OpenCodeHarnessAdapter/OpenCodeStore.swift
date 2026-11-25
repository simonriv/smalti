import Foundation
import SQLiteReader
import SmaltiCore

/// OpenCode 2.x's database (`opencode.db`): top-level sessions of `session_v2`, with the model and provider of each
/// one's last assistant message, read from `session_message.data` (JSON). A 1.x database (`session`) is an unknown
/// schema: OpenCode 2.x migrates it on its own (spec F6).
struct OpenCodeStore {
    static let table = "session_v2"
    static let requiredColumns = [
        "id", "parent_id", "directory", "title", "time_created", "time_updated", "time_archived", "tokens_input",
        "tokens_output", "tokens_cache_read",
    ]

    struct Row {
        let id: String
        let directory: String
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let model: String?
        let provider: String?
        let input: Int
        let output: Int
    }

    let database: URL
    let harness = HarnessID.opencode

    func rows(updatedSince since: Date = .distantPast) throws(HarnessError) -> [Row] {
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw .storeMissing(harness: harness, path: database.path)
        }
        let reader = SQLiteReader(url: database)
        do {
            let columns = try reader.columns(of: Self.table)
            if columns.isEmpty {
                throw HarnessError.unknownSchema(harness: harness, path: database.path, missing: Self.table)
            }
            if let missing = Self.requiredColumns.first(where: { !columns.contains($0) }) {
                throw HarnessError.unknownSchema(harness: harness, path: database.path, missing: missing)
            }
            return try reader.rows(Self.query, [.integer(Int64(max(since.timeIntervalSince1970, 0) * 1000))])
                .compactMap(row)
        } catch let error as HarnessError {
            throw error
        } catch {
            throw .unreadable(harness: harness, path: database.path, reason: String(describing: error))
        }
    }

    /// The last assistant message's model, guarded with `json_valid` so a broken message never fails the query.
    private static let lastModel = """
        (select case when json_valid(m.data) then json_extract(m.data, '$.model.%@') end from session_message m
         where m.session_id = s.id and m.type = 'assistant' order by m.seq desc limit 1)
        """

    private static let query = """
        select s.id, s.directory, s.title, s.time_created, s.time_updated, \(String(format: lastModel, "id")),
               \(String(format: lastModel, "providerID")), s.tokens_input + s.tokens_cache_read, s.tokens_output
        from session_v2 s
        where coalesce(s.parent_id, '') = '' and s.time_archived is null and s.time_updated >= ?
        order by s.time_updated desc
        """

    private func row(_ row: SQLiteRow) -> Row? {
        guard let id = row[text: 0], let directory = row[text: 1], let created = row[integer: 3],
            let updated = row[integer: 4]
        else { return nil }
        return Row(
            id: id, directory: directory, title: row[text: 2] ?? "",
            createdAt: Date(timeIntervalSince1970: TimeInterval(created) / 1000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(updated) / 1000), model: row[text: 5],
            provider: row[text: 6], input: Int(row[integer: 7] ?? 0), output: Int(row[integer: 8] ?? 0))
    }
}
