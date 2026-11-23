/// What the word at the cursor completes, inside a command described by a spec.
public enum CompletionTarget: Equatable, Sendable {
    case subcommandOrOption(prefix: String, spec: CompletionSpec)
    case optionValue(OptionSpec, prefix: String)
    case argument(ArgSpec, prefix: String)
}

public enum CompletionEngine {
    /// Walks the words before the cursor down the spec: subcommands go deeper, options skip their values,
    /// other words fill the positional arguments. Nil when the line is not this spec's command.
    public static func target(for line: InputLine, spec: CompletionSpec) -> CompletionTarget? {
        let words = line.currentCommand.filter { $0.range.upperBound < line.cursor || $0.range.isEmpty }
        guard let command = words.first, spec.name.contains(command.text) else { return nil }
        var walk = SpecWalk(spec: spec)
        for token in words.dropFirst() { walk.consume(token.text) }
        return walk.target(prefix: line.wordBeforeCursor)
    }

    /// The fixed suggestions a target offers; templates and generators are resolved by the caller.
    public static func suggestions(for target: CompletionTarget) -> [Suggestion] {
        switch target {
        case .subcommandOrOption(let prefix, let spec):
            prefix.hasPrefix("-")
                ? spec.options.flatMap { option in
                    option.names.map { Suggestion(name: $0, description: option.description) }
                }
                : spec.subcommands.map { Suggestion(name: $0.name[0], description: $0.description) }
                    + (spec.args.first?.suggestions ?? [])
        case .optionValue(let option, _): option.args.first?.suggestions ?? []
        case .argument(let arg, _): arg.suggestions
        }
    }

    /// Prefix matches first, then fuzzy ones by score; each group by how often history used the word, then in
    /// the spec's order. Suggestions that match neither way are dropped.
    public static func rank(_ suggestions: [Suggestion], prefix: String, history: HistoryIndex?) -> [Suggestion] {
        let ranked = suggestions.enumerated().compactMap { offset, suggestion -> RankedSuggestion? in
            let isPrefix = suggestion.name.hasPrefix(prefix)
            guard isPrefix || fuzzyScore(prefix, in: suggestion.name) != nil else { return nil }
            return RankedSuggestion(
                suggestion: suggestion, isPrefix: isPrefix,
                fuzzy: isPrefix ? 0 : fuzzyScore(prefix, in: suggestion.name) ?? 0,
                uses: history?.uses(ofWord: suggestion.name) ?? 0, offset: offset)
        }
        return ranked.sorted(by: RankedSuggestion.precedes).map(\.suggestion)
    }

    /// The line with the whole word at the cursor replaced by the suggestion, as zsh does without
    /// `COMPLETE_IN_WORD`. The name is quoted the way the word is: inside its opening quote (closed after the
    /// value, unless the value is a folder to keep descending) or with zsh's metacharacters escaped. A space
    /// follows unless the value ends a folder (`/`) or awaits a value (`=`). `insertValue` is literal shell text:
    /// it is not escaped, and `{cursor}` places the cursor.
    public static func insertion(of suggestion: Suggestion, into line: InputLine) -> InputLine {
        let word = line.currentWord
        guard let literal = suggestion.insertValue else {
            let quoted = ShellQuoting.word(suggestion.name, opening: word.openingQuote)
            let isOpenEnded = suggestion.name.hasSuffix("/") || suggestion.name.hasSuffix("=")
            let closing = isOpenEnded ? "" : (word.openingQuote.map(String.init) ?? "") + " "
            return replace(word, in: line, with: quoted + closing, cursorAt: nil)
        }
        let marker = literal.range(of: "{cursor}").map { literal.unicodeScalars[..<$0.lowerBound].count }
        let value = literal.replacingOccurrences(of: "{cursor}", with: "")
        return replace(word, in: line, with: marker == nil ? value + " " : value, cursorAt: marker)
    }

    /// The word at the cursor extended to `prefix` (quoted like the word), with nothing after it: the menu's
    /// common prefix.
    public static func insertion(ofPrefix prefix: String, into line: InputLine) -> InputLine {
        let word = line.currentWord
        return replace(word, in: line, with: ShellQuoting.word(prefix, opening: word.openingQuote), cursorAt: nil)
    }

    private static func replace(_ word: Token, in line: InputLine, with value: String, cursorAt marker: Int?)
        -> InputLine
    {
        let scalars = Array(line.text.unicodeScalars)
        let before = String(String.UnicodeScalarView(scalars[..<word.range.lowerBound]))
        let after = String(String.UnicodeScalarView(scalars[word.range.upperBound...]))
        let cursor = word.range.lowerBound + (marker ?? value.unicodeScalars.count)
        return InputLine(text: before + value + after, cursor: cursor)
    }

    private struct RankedSuggestion {
        let suggestion: Suggestion
        let isPrefix: Bool
        let fuzzy: Int
        let uses: Int
        let offset: Int

        static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
            if lhs.fuzzy != rhs.fuzzy { return lhs.fuzzy > rhs.fuzzy }
            if lhs.uses != rhs.uses { return lhs.uses > rhs.uses }
            return lhs.offset < rhs.offset
        }
    }
}

/// The position reached in a spec after the words already typed.
private struct SpecWalk {
    var spec: CompletionSpec
    var pendingOption: OptionSpec?
    var argumentIndex = 0

    init(spec: CompletionSpec) {
        self.spec = spec
    }

    mutating func consume(_ word: String) {
        if pendingOption != nil {
            pendingOption = nil
        } else if word.hasPrefix("-") {
            let name = word.split(separator: "=", maxSplits: 1).first.map(String.init) ?? word
            let option = spec.options.first { $0.names.contains(name) }
            if let option, !option.args.isEmpty, !word.contains("=") { pendingOption = option }
        } else if let subcommand = spec.subcommands.first(where: { $0.name.contains(word) }) {
            spec = subcommand
            argumentIndex = 0
        } else if argumentIndex < spec.args.count, !spec.args[argumentIndex].isVariadic {
            argumentIndex += 1
        }
    }

    func target(prefix: String) -> CompletionTarget? {
        if let pendingOption { return .optionValue(pendingOption, prefix: prefix) }
        if prefix.hasPrefix("-") || (!spec.subcommands.isEmpty && argumentIndex == 0) {
            return .subcommandOrOption(prefix: prefix, spec: spec)
        }
        if argumentIndex < spec.args.count { return .argument(spec.args[argumentIndex], prefix: prefix) }
        return spec.subcommands.isEmpty ? nil : .subcommandOrOption(prefix: prefix, spec: spec)
    }
}
