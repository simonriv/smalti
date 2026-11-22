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
/// Case and accents are ignored. Each matched character earns +10 when it follows the previous match directly
/// and +8 when it starts a word; each skipped character between matches costs 1; a title that starts with the
/// query earns +15. Matching is greedy from the left. An empty query returns every command in its given order,
/// and ties keep that order.
public func fuzzyMatch(_ query: String, in commands: [Command]) -> [RankedCommand] {
    let needle = Array(folded(query))
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
    let haystack = Array(folded([command.title, command.subtitle].compactMap { $0 }.joined(separator: " ")))
    guard let matched = subsequencePositions(of: needle, in: haystack) else { return nil }
    let titleBonus = folded(command.title).hasPrefix(String(needle)) ? titlePrefixBonus : 0
    return pairwiseScore(matched, in: haystack) + titleBonus
}

/// Indices of the leftmost match of `needle` in `haystack`, or `nil` when it is not a subsequence.
private func subsequencePositions(of needle: [Character], in haystack: [Character]) -> [Int]? {
    var positions: [Int] = []
    var searchFrom = 0
    for character in needle {
        guard let index = haystack[searchFrom...].firstIndex(of: character) else { return nil }
        positions.append(index)
        searchFrom = index + 1
    }
    return positions
}

private func pairwiseScore(_ positions: [Int], in haystack: [Character]) -> Int {
    var total = 0
    var previous: Int?
    for position in positions {
        if startsWord(at: position, in: haystack) { total += wordStartBonus }
        if let previous {
            let skipped = position - previous - 1
            total += skipped == 0 ? consecutiveBonus : -skipped * skippedCharacterPenalty
        }
        previous = position
    }
    return total
}

private func startsWord(at index: Int, in haystack: [Character]) -> Bool {
    index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
}
