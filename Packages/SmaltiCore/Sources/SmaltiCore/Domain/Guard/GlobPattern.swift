/// A shell glob over one path component: `*`, `?` and `[…]` (with `!` or `^` to negate). As in zsh and bash, a
/// leading `.` must be written: `*` does not match `.env`.
enum GlobPattern {
    static let wildcards: Set<Character> = ["*", "?", "["]

    static func hasWildcard(_ text: String) -> Bool {
        text.contains { wildcards.contains($0) }
    }

    static func matches(_ pattern: String, _ name: String) -> Bool {
        if name.hasPrefix(".") && !pattern.hasPrefix(".") { return false }
        return matches(Array(pattern)[...], Array(name)[...])
    }

    private static func matches(_ pattern: ArraySlice<Character>, _ name: ArraySlice<Character>) -> Bool {
        guard let first = pattern.first else { return name.isEmpty }
        switch first {
        case "*":
            let rest = pattern.dropFirst()
            return name.indices.contains { matches(rest, name[$0...]) } || matches(rest, name[name.endIndex...])
        case "?":
            return !name.isEmpty && matches(pattern.dropFirst(), name.dropFirst())
        case "[":
            return bracket(pattern, name)
        default:
            return name.first == first && matches(pattern.dropFirst(), name.dropFirst())
        }
    }

    /// `[abc]`, `[a-z]`, `[!x]`; an unclosed `[` is a literal.
    private static func bracket(_ pattern: ArraySlice<Character>, _ name: ArraySlice<Character>) -> Bool {
        guard let close = pattern.dropFirst(2).firstIndex(of: "]") else {
            return name.first == "[" && matches(pattern.dropFirst(), name.dropFirst())
        }
        guard let character = name.first else { return false }
        var set = pattern[pattern.index(after: pattern.startIndex)..<close]
        let isNegated = set.first == "!" || set.first == "^"
        if isNegated { set = set.dropFirst() }
        return contains(set, character) != isNegated && matches(pattern[(close + 1)...], name.dropFirst())
    }

    private static func contains(_ set: ArraySlice<Character>, _ character: Character) -> Bool {
        var index = set.startIndex
        while index < set.endIndex {
            if index + 2 < set.endIndex, set[index + 1] == "-" {
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
