import Foundation

/// How a command has been used: what prediction and ⌃R rank by.
public struct CommandStats: Equatable, Sendable {
    public let command: String
    public internal(set) var uses: Int
    public internal(set) var lastUsed: Date
    public internal(set) var lastExit: Int?
    public internal(set) var usesByDirectory: [String: Int]

    public init(command: String, uses: Int, lastUsed: Date, lastExit: Int?, usesByDirectory: [String: Int]) {
        self.command = command
        self.uses = uses
        self.lastUsed = lastUsed
        self.lastExit = lastExit
        self.usesByDirectory = usesByDirectory
    }
}

/// The most recent `limit` entries, counted by command, by directory and by what each pane ran next.
///
/// A successor is the next command of the same pane, filed under the directory of the command before it. A fix
/// is a successor of a failed command that is a different command. Evicting the oldest entry forgets its uses and
/// the pair it formed with the command before it, so every count stays the count of the kept window.
public struct HistoryIndex: Sendable {
    private struct Pair: Hashable, Sendable {
        let directory: String
        let previous: String
        let next: String
        let isFix: Bool
    }

    private let limit: Int
    private var entries: [HistoryEntry] = []
    private var pairs: [Pair?] = []
    private var head = 0
    private var stats: [String: CommandStats] = [:]
    private var successorCounts: [String: [String: [String: Int]]] = [:]
    private var fixCounts: [String: [String: Int]] = [:]
    private var wordUses: [String: Int] = [:]
    private var lastByPane: [PaneID: HistoryEntry] = [:]

    public init(entries: [HistoryEntry], limit: Int) {
        self.limit = max(limit, 0)
        for entry in entries.suffix(self.limit) { append(entry) }
    }

    public var count: Int { entries.count - head }

    public mutating func append(_ entry: HistoryEntry) {
        guard limit > 0 else { return }
        let pair = lastByPane[entry.pane].map { previous in
            Pair(
                directory: previous.directory, previous: previous.command, next: entry.command,
                isFix: previous.hasFailed && previous.command != entry.command)
        }
        entries.append(entry)
        pairs.append(pair)
        lastByPane[entry.pane] = entry
        tally(entry)
        if let pair { tally(pair, by: 1) }
        if count > limit { evictOldest() }
    }

    public func stats(for command: String) -> CommandStats? { stats[command] }

    /// Every command used in `directory`, or every command when it is nil, in no particular order.
    public func commands(in directory: String?) -> [CommandStats] {
        guard let directory else { return Array(stats.values) }
        return stats.values.filter { ($0.usesByDirectory[directory] ?? 0) > 0 }
    }

    public func successors(of command: String, in directory: String) -> [String: Int] {
        successorCounts[directory]?[command] ?? [:]
    }

    public func fixes(after failed: String) -> [String: Int] { fixCounts[failed] ?? [:] }

    /// How many kept uses contain `word` as one of their space-separated words: the completion tiebreaker.
    public func uses(ofWord word: String) -> Int { wordUses[word] ?? 0 }

    private mutating func tally(_ entry: HistoryEntry) {
        var current =
            stats[entry.command]
            ?? CommandStats(command: entry.command, uses: 0, lastUsed: entry.date, lastExit: nil, usesByDirectory: [:])
        current.uses += 1
        // A new command starts with this entry's date, so its first use always lands here.
        if entry.date >= current.lastUsed {
            current.lastUsed = entry.date
            current.lastExit = entry.exit
        }
        current.usesByDirectory[entry.directory, default: 0] += 1
        stats[entry.command] = current
        countWords(of: entry.command, by: 1)
    }

    private mutating func tally(_ pair: Pair, by step: Int) {
        successorCounts[pair.directory, default: [:]][pair.previous, default: [:]][pair.next, default: 0] += step
        if successorCounts[pair.directory]?[pair.previous]?[pair.next] == 0 {
            successorCounts[pair.directory]?[pair.previous]?[pair.next] = nil
        }
        guard pair.isFix else { return }
        fixCounts[pair.previous, default: [:]][pair.next, default: 0] += step
        if fixCounts[pair.previous]?[pair.next] == 0 { fixCounts[pair.previous]?[pair.next] = nil }
    }

    private mutating func evictOldest() {
        let oldest = entries[head]
        if let pair = pairs[head] { tally(pair, by: -1) }
        uncount(oldest)
        head += 1
        // The successor of the evicted entry loses its predecessor: forget that pair too.
        if head < entries.count, let pair = pairs[head] {
            tally(pair, by: -1)
            pairs[head] = nil
        }
        compactIfNeeded()
    }

    private mutating func uncount(_ entry: HistoryEntry) {
        guard var current = stats[entry.command] else { return }
        current.uses -= 1
        current.usesByDirectory[entry.directory, default: 1] -= 1
        if current.usesByDirectory[entry.directory] == 0 { current.usesByDirectory[entry.directory] = nil }
        stats[entry.command] = current.uses > 0 ? current : nil
        countWords(of: entry.command, by: -1)
    }

    private mutating func countWords(of command: String, by step: Int) {
        for word in Set(command.split(separator: " ")) {
            let key = String(word)
            wordUses[key, default: 0] += step
            if wordUses[key] == 0 { wordUses[key] = nil }
        }
    }

    /// Drops evicted slots once they are half the storage, so eviction stays amortized O(1).
    private mutating func compactIfNeeded() {
        guard head > 1024, head * 2 > entries.count else { return }
        entries.removeFirst(head)
        pairs.removeFirst(head)
        head = 0
    }
}
