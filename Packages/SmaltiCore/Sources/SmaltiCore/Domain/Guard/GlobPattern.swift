/// A shell glob over one path component: `*`, `?` and `[…]` (with `!` or `^` to negate). As in zsh and bash, a
/// leading `.` must be written: `*` does not match `.env`. Matching is the greedy two-pointer algorithm, linear in
/// practice: an agent's pattern can never make it backtrack exponentially (review 1).
enum GlobPattern {
    static let wildcards: Set<Character> = ["*", "?", "["]

    static func hasWildcard(_ text: String) -> Bool {
        text.contains { wildcards.contains($0) }
    }

    static func matches(_ pattern: String, _ name: String) -> Bool {
        if name.hasPrefix(".") && !pattern.hasPrefix(".") { return false }
        return matches(tokens(of: pattern), Array(name))
    }

    private enum Token: Equatable {
        case star
        case any
        case literal(Character)
        case set([Character], isNegated: Bool)

        func accepts(_ character: Character) -> Bool {
            switch self {
            case .star, .any: true
            case .literal(let literal): literal == character
            case .set(let members, let isNegated): GlobPattern.contains(members, character) != isNegated
            }
        }
    }

    private static func matches(_ pattern: [Token], _ name: [Character]) -> Bool {
        var (p, n) = (0, 0)
        var lastStar: Int?
        var resume = 0
        while n < name.count {
            if p < pattern.count, pattern[p] == .star {
                lastStar = p
                resume = n
                p += 1
            } else if p < pattern.count, pattern[p].accepts(name[n]) {
                p += 1
                n += 1
            } else if let star = lastStar {
                p = star + 1
                resume += 1
                n = resume
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == .star { p += 1 }
        return p == pattern.count
    }

    /// The pattern as tokens, consecutive stars folded into one; an unclosed `[` is a literal.
    private static func tokens(of pattern: String) -> [Token] {
        let characters = Array(pattern)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "*" where tokens.last != .star: tokens.append(.star)
            case "*": continue
            case "?": tokens.append(.any)
            case "[":
                if let (set, next) = bracket(characters, from: index) {
                    tokens.append(set)
                    index = next
                } else {
                    tokens.append(.literal("["))
                }
            default: tokens.append(.literal(character))
            }
        }
        return tokens
    }

    /// The set that starts after `[` at `start`, and the index after its `]`.
    private static func bracket(_ characters: [Character], from start: Int) -> (Token, Int)? {
        var index = start
        let isNegated = index < characters.count && (characters[index] == "!" || characters[index] == "^")
        if isNegated { index += 1 }
        guard let close = characters[min(index + 1, characters.count)...].firstIndex(of: "]") else { return nil }
        return (.set(Array(characters[index..<close]), isNegated: isNegated), close + 1)
    }

    fileprivate static func contains(_ set: [Character], _ character: Character) -> Bool {
        var index = 0
        while index < set.count {
            if index + 2 < set.count, set[index + 1] == "-" {
                if set[index] <= character && character <= set[index + 2] { return true }
                index += 3
            } else {
                if set[index] == character { return true }
                index += 1
            }
        }
        return false
    }
}
