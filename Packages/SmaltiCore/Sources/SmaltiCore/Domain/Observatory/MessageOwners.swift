/// Which session a reply belongs to, across sessions. A fork (`claude --resume … --fork-session`) copies its
/// source's replies, ids included, into its own transcript: the first session to claim an id keeps it, and
/// sessions derived from others are read after them, so the copies stay with the source.
public struct MessageOwners: Codable, Equatable, Sendable {
    private var owners: [String: String] = [:]

    public init() {}

    /// `records` without the replies another session already owns; this session now owns the rest.
    public mutating func claim(_ records: [TranscriptRecord], for session: String) -> [TranscriptRecord] {
        records.filter { record in
            guard case .assistantTurn(let turn) = record else { return true }
            let owner = owners[turn.messageID, default: session]
            owners[turn.messageID] = owner
            return owner == session
        }
    }

    /// Forgets what `session` owns, before its transcript is read again from the start.
    public mutating func release(_ session: String) {
        owners = owners.filter { $0.value != session }
    }

    /// The same items, each after the items of the sessions it was forked from (a chain `s ← f1 ← f2` reads `s`,
    /// `f1`, `f2`); otherwise in their original order. Sources outside the batch and cycles change nothing.
    public static func sourcesFirst<Item>(
        _ items: [Item], session: (Item) -> String, sources: (Item) -> [String]
    ) -> [Item] {
        var pending = items
        var placed: [Item] = []
        while !pending.isEmpty {
            let waiting = Set(pending.map(session))
            let ready =
                pending.firstIndex { item in
                    sources(item).allSatisfy { !waiting.contains($0) || $0 == session(item) }
                } ?? 0
            placed.append(pending.remove(at: ready))
        }
        return placed
    }
}
