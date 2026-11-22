import Foundation

/// A command that matched a query, with how well.
public struct RankedCommand: Hashable, Sendable {
    public let command: Command
    public let score: Int

    public init(command: Command, score: Int) {
        self.command = command
        self.score = score
    }
}

private let consecutiveBonus = 10
private let wordStartBonus = 8
private let titlePrefixBonus = 15
private let skippedCharacterPenalty = 1

/// The commands whose title and subtitle contain `query` as a subsequence, best first.
///
/// Case, accents and surrounding whitespace are ignored. The score is that of the best alignment of the query
/// in `title + " " + subtitle`: each matched character earns +10 when it follows the previous match directly and
/// +8 when it starts a word; each character skipped between two matches costs 1 (characters before the first
/// match cost nothing); a title that starts with the query earns +15. An empty query returns every command in
/// its given order, and ties keep that order.
public func fuzzyMatch(_ query: String, in commands: [Command]) -> [RankedCommand] {
    let needle = Array(folded(query.trimmingCharacters(in: .whitespacesAndNewlines)))
    let ranked = commands.enumerated().compactMap { offset, command in
        score(needle, for: command).map { (offset: offset, ranked: RankedCommand(command: command, score: $0)) }
    }
    return ranked.sorted { ($1.ranked.score, $0.offset) < ($0.ranked.score, $1.offset) }.map(\.ranked)
}

private func folded(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

private func score(_ needle: [Character], for command: Command) -> Int? {
    guard !needle.isEmpty else { return 0 }
    let title = folded(command.title)
    let haystack = Array(folded([command.title, command.subtitle].compactMap { $0 }.joined(separator: " ")))
    guard let alignment = bestAlignmentScore(of: needle, in: haystack) else { return nil }
    return alignment + (title.hasPrefix(String(needle)) ? titlePrefixBonus : 0)
}

/// Best score over every way of matching `needle` as a subsequence of `haystack`, or `nil` when there is none.
///
/// Dynamic program in O(needle × haystack): `previous[i]` is the best score with the prior needle character
/// matched at `i`. A character matched at `i` either follows a match at `i - 1` (consecutive bonus) or a match
/// at `p < i - 1` (penalty `i - p - 1`, rewritten as `(previous[p] + p) + 1 - i` so a running maximum suffices;
/// that form relies on the penalty being exactly one per character).
private func bestAlignmentScore(of needle: [Character], in haystack: [Character]) -> Int? {
    var previous: [Int?] = haystack.indices.map { index in
        haystack[index] == needle[0] ? wordStartScore(at: index, in: haystack) : nil
    }
    for character in needle.dropFirst() {
        var current = [Int?](repeating: nil, count: haystack.count)
        var bestDistant: Int?
        for index in haystack.indices {
            if index >= 2, let score = previous[index - 2] {
                bestDistant = max(bestDistant ?? .min, score + index - 2)
            }
            guard haystack[index] == character else { continue }
            let afterConsecutive = index >= 1 ? previous[index - 1].map { $0 + consecutiveBonus } : nil
            let afterSkipping = bestDistant.map { $0 + skippedCharacterPenalty - index }
            guard let before = [afterConsecutive, afterSkipping].compactMap({ $0 }).max() else { continue }
            current[index] = before + wordStartScore(at: index, in: haystack)
        }
        previous = current
    }
    return previous.compactMap { $0 }.max()
}

private func wordStartScore(at index: Int, in haystack: [Character]) -> Int {
    let startsWord = index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
    return startsWord ? wordStartBonus : 0
}
