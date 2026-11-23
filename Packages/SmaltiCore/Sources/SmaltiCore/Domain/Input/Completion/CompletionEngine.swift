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
        let word = line.currentWord
        let words = line.currentCommand.filter { $0.range.upperBound <= word.range.lowerBound }
        guard let command = words.first, spec.name.contains(command.text) else { return nil }
        var walk = SpecWalk(spec: spec)
        for token in words.dropFirst() { walk.consume(token.text) }
        return walk.target(prefix: word.text)
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
        let usage = history.map { wordUsage(in: $0) } ?? [:]
        let ranked = suggestions.enumerated().compactMap { offset, suggestion -> RankedSuggestion? in
            let isPrefix = suggestion.name.hasPrefix(prefix)
            guard isPrefix || fuzzyScore(prefix, in: suggestion.name) != nil else { return nil }
            return RankedSuggestion(
                suggestion: suggestion, isPrefix: isPrefix,
                fuzzy: isPrefix ? 0 : fuzzyScore(prefix, in: suggestion.name) ?? 0,
                uses: usage[suggestion.name] ?? 0, offset: offset)
        }
        return ranked.sorted(by: RankedSuggestion.precedes).map(\.suggestion)
    }

    /// The line with the word at the cursor replaced by the suggestion. A space follows unless the value ends a
    /// folder (`/`) or awaits a value (`=`); spaces in a name are escaped outside quotes (`insertValue` is literal
    /// shell text); `{cursor}` places the cursor.
    public static func insertion(of suggestion: Suggestion, into line: InputLine) -> InputLine {
        let word = line.currentWord
        let raw = suggestion.insertValue ?? suggestion.name
        let marked = raw.contains("{cursor}")
        var value =
            word.isQuoted || suggestion.insertValue != nil ? raw : raw.replacingOccurrences(of: " ", with: "\\ ")
        if !marked && !(value.hasSuffix("/") || value.hasSuffix("=")) { value += " " }
        let scalars = Array(line.text.unicodeScalars)
        let before = String(String.UnicodeScalarView(scalars[..<word.range.lowerBound]))
        let after = String(String.UnicodeScalarView(scalars[line.cursor...]))
        let cursorOffset = value.range(of: "{cursor}").map { value.unicodeScalars[..<$0.lowerBound].count }
        value = value.replacingOccurrences(of: "{cursor}", with: "")
        let cursor = word.range.lowerBound + (cursorOffset ?? value.unicodeScalars.count)
        return InputLine(text: before + value + after, cursor: cursor)
    }

    /// How many history uses contain each word: what breaks ties between equally good suggestions.
    private static func wordUsage(in history: HistoryIndex) -> [String: Int] {
        history.commands(in: nil).reduce(into: [:]) { usage, stats in
            for word in Set(stats.command.split(separator: " ")) { usage[String(word), default: 0] += stats.uses }
        }
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
