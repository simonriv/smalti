import Foundation

public enum HistoryScope: Equatable, Sendable {
    case directory(String)
    case all
}

/// One ⌃R result: the command's stats and where the query matched, in characters of the command.
public struct HistoryHit: Equatable, Sendable {
    public let stats: CommandStats
    public let matched: [Range<Int>]

    public init(stats: CommandStats, matched: [Range<Int>]) {
        self.stats = stats
        self.matched = matched
    }
}

/// ⌃R: fuzzy search over the commands of a scope, best score first, then the most recently used.
public enum HistorySearch {
    /// The palette scrolls through at most this many; computing match ranges for every command would cost a
    /// keystroke's time on a history of tens of thousands.
    public static let maximumHits = 200

    public static func search(_ query: String, scope: HistoryScope, in index: HistoryIndex) -> [HistoryHit] {
        let candidates = index.commands(in: directory(of: scope))
        let scored = candidates.compactMap { stats in
            fuzzyScore(query, in: stats.command).map { (stats: stats, score: $0) }
        }
        return scored.sorted { ($0.score, $0.stats.lastUsed) > ($1.score, $1.stats.lastUsed) }
            .prefix(maximumHits).map {
                HistoryHit(stats: $0.stats, matched: fuzzyMatchedRanges(query, in: $0.stats.command))
            }
    }

    /// "hace N min" under an hour (at least 1), "hace N h" under a day, then "ayer" or "hace N días" by calendar day.
    public static func ago(_ date: Date, now: Date, calendar: Calendar) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 3_600 { return "hace \(max(Int(elapsed / 60), 1)) min" }
        if elapsed < 86_400 { return "hace \(Int(elapsed / 3_600)) h" }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        return days <= 1 ? "ayer" : "hace \(days) días"
    }

    private static func directory(of scope: HistoryScope) -> String? {
        switch scope {
        case .directory(let path): path
        case .all: nil
        }
    }
}
