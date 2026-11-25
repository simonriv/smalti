/// Gives each part of the command line its role (spec F5.6, "Tokenizador"). Whether a command exists is left to
/// zsh, which knows the shell's aliases and functions; subcommands come from the specs already loaded, never waited
/// for.
public enum LineHighlighter {
    /// The words checked against the disk per line.
    public static let maximumPathCandidates = 16

    public static func plan(for text: String, specs: (String) -> CompletionSpec?) -> HighlightPlan {
        // The walker lives only inside this call, so `specs` never outlives it.
        withoutActuallyEscaping(specs) { specs in
            var walker = Walker(specs: specs)
            for lexeme in HighlightLexer.lexemes(in: text) { walker.visit(lexeme) }
            return walker.finish()
        }
    }
}

private struct Walker {
    /// Words that run the command after them: the next word is still in command position.
    private static let precommands: Set<String> = [
        "sudo", "doas", "time", "nohup", "exec", "command", "builtin", "noglob", "nice", "env",
    ]
    /// Reserved words after which a command comes: they are colored as commands and keep the command position.
    private static let leadingReservedWords: Set<String> = [
        "if", "then", "else", "elif", "do", "while", "until", "!", "{", "}",
    ]
    /// Precommand options that take the next word as their value (`sudo -u root ls`).
    private static let precommandValueOptions: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-C", "-h", "-p", "-U", "-r", "-t", "-T", "-D", "-R"], "doas": ["-u", "-C"],
        "nice": ["-n"], "env": ["-u", "-C", "-S", "-P"], "exec": ["-a"],
    ]
    private static let globCharacters: Set<Unicode.Scalar> = ["*", "?", "["]

    let specs: (String) -> CompletionSpec?
    private var spans: [HighlightSpan] = []
    private var candidates: [PathCandidate] = []
    private var withoutSpec: [String] = []
    private var isCommandPosition = true
    private var spec: CompletionSpec?
    private var positionals = 0
    /// Words still owed to the last option's arguments.
    private var optionArguments = 0
    private var isRedirectionTarget = false
    /// `sudo -E git`: a precommand's own options keep the command position; this names that precommand.
    private var precommand: String?
    /// The precommand option just read takes the next word as its value.
    private var isPrecommandValueNext = false

    init(specs: @escaping (String) -> CompletionSpec?) {
        self.specs = specs
    }

    mutating func visit(_ lexeme: Lexeme) {
        switch lexeme.kind {
        case .controlOperator:
            spans.append(HighlightSpan(range: lexeme.range, role: .operator))
            startCommand()
        case .redirection:
            spans.append(HighlightSpan(range: lexeme.range, role: .operator))
            isRedirectionTarget = true
        case .arithmetic:
            arithmetic(lexeme)
        case .word(let parts):
            visitWord(lexeme, parts: parts)
        }
    }

    func finish() -> HighlightPlan {
        HighlightPlan(
            spans: spans.sorted { $0.range.lowerBound < $1.range.lowerBound }, pathCandidates: candidates,
            commandsWithoutSpec: withoutSpec)
    }

    private mutating func startCommand() {
        isCommandPosition = true
        spec = nil
        positionals = 0
        optionArguments = 0
        precommand = nil
        isPrecommandValueNext = false
        isRedirectionTarget = false
    }

    /// `((` and its closing `))` are operators; the expression inside has no role.
    private mutating func arithmetic(_ lexeme: Lexeme) {
        let length = lexeme.range.count
        spans.append(HighlightSpan(range: lexeme.range.lowerBound..<(lexeme.range.lowerBound + 2), role: .operator))
        if length >= 4, lexeme.text.hasSuffix("))") {
            spans.append(HighlightSpan(range: (lexeme.range.upperBound - 2)..<lexeme.range.upperBound, role: .operator))
        }
        isCommandPosition = false
    }

    // MARK: - Words

    private mutating func visitWord(_ lexeme: Lexeme, parts: [WordPart]) {
        if isRedirectionTarget {
            isRedirectionTarget = false
            argument(lexeme, parts: parts)
        } else if isCommandPosition, isPrecommandValueNext {
            isPrecommandValueNext = false
            colorParts(parts)
        } else if isCommandPosition, let name = precommand, isOption(lexeme, parts: parts) {
            spans.append(HighlightSpan(range: lexeme.range, role: .option))
            isPrecommandValueNext = Self.precommandValueOptions[name]?.contains(lexeme.text) ?? false
        } else if isCommandPosition {
            commandWord(lexeme, parts: parts)
        } else if isOption(lexeme, parts: parts) {
            option(lexeme, parts: parts)
        } else if optionArguments > 0 {
            optionArguments -= 1
            argument(lexeme, parts: parts)
        } else if positionals == 0, let sub = subcommand(named: Self.literal(lexeme, parts: parts)) {
            spans.append(HighlightSpan(range: lexeme.range, role: .subcommand))
            spec = sub
        } else if positionals == 0, spec?.args.first?.isCommand == true {
            startCommand()
            commandWord(lexeme, parts: parts)
        } else {
            positionals += 1
            argument(lexeme, parts: parts)
        }
    }

    private mutating func commandWord(_ lexeme: Lexeme, parts: [WordPart]) {
        if let name = assignmentName(lexeme, parts: parts) {
            spans.append(
                HighlightSpan(range: lexeme.range.lowerBound..<(lexeme.range.lowerBound + name), role: .variable))
            // The name and `=` are a bare part, which `colorParts` leaves alone; the value keeps its own colors.
            colorParts(parts)
            return
        }
        if parts.contains(where: { $0.kind == .variable }) {
            // `$EDITOR file`: only the shell knows what runs; the word keeps its parts' colors.
            colorParts(parts)
            isCommandPosition = false
            return
        }
        spans.append(HighlightSpan(range: lexeme.range, role: .command))
        let name = Self.literal(lexeme, parts: parts)
        if Self.leadingReservedWords.contains(name) { return }
        precommand = Self.precommands.contains(name) ? name : nil
        if precommand != nil { return }
        isCommandPosition = false
        spec = specs(name)
        if spec == nil, !name.isEmpty { withoutSpec.append(name) }
    }

    /// The length of `NAME` in a leading `NAME=value`, which is an assignment, not a command.
    private func assignmentName(_ lexeme: Lexeme, parts: [WordPart]) -> Int? {
        guard let first = parts.first, first.kind == .bare else { return nil }
        let scalars = Array(lexeme.text.unicodeScalars)
        guard let equals = scalars.firstIndex(of: "="), equals > 0, equals < first.range.count else { return nil }
        let isName = scalars[..<equals].enumerated().allSatisfy { index, scalar in
            scalar == "_" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                || (index > 0 && ("0"..."9").contains(scalar))
        }
        return isName ? equals : nil
    }

    private func isOption(_ lexeme: Lexeme, parts: [WordPart]) -> Bool {
        guard parts.first?.kind == .bare, lexeme.text.hasPrefix("-") else { return false }
        return lexeme.text != "-" && lexeme.text != "--"
    }

    /// `--name=value` colors only `--name=`; the option's spec decides how many words it takes after it.
    private mutating func option(_ lexeme: Lexeme, parts: [WordPart]) {
        let scalars = Array(lexeme.text.unicodeScalars)
        if let equals = scalars.firstIndex(of: "="), lexeme.text.hasPrefix("--") {
            let name = lexeme.range.lowerBound..<(lexeme.range.lowerBound + equals + 1)
            spans.append(HighlightSpan(range: name, role: .option))
            colorParts(parts.filter { $0.range.lowerBound >= name.upperBound })
            return
        }
        spans.append(HighlightSpan(range: lexeme.range, role: .option))
        let known = spec?.options.first { $0.names.contains(lexeme.text) }
        optionArguments = known?.args.count ?? 0
    }

    private func subcommand(named name: String) -> CompletionSpec? {
        spec?.subcommands.first { $0.name.contains(name) }
    }

    private mutating func argument(_ lexeme: Lexeme, parts: [WordPart]) {
        colorParts(parts)
        guard candidates.count < LineHighlighter.maximumPathCandidates, isPathLike(lexeme, parts: parts) else {
            return
        }
        candidates.append(PathCandidate(word: Self.literal(lexeme, parts: parts), range: lexeme.range))
    }

    /// Without variables, globs or `$'…'` the word is literal text that may name a file.
    private func isPathLike(_ lexeme: Lexeme, parts: [WordPart]) -> Bool {
        guard !parts.contains(where: { $0.kind == .variable }), !lexeme.text.hasPrefix("$'") else { return false }
        let bare = parts.filter { $0.kind == .bare }.flatMap {
            Array(lexeme.text.unicodeScalars)[offsets($0, in: lexeme)]
        }
        return !bare.contains { Self.globCharacters.contains($0) }
    }

    private mutating func colorParts(_ parts: [WordPart]) {
        for part in parts {
            switch part.kind {
            case .quoted: spans.append(HighlightSpan(range: part.range, role: .string))
            case .variable: spans.append(HighlightSpan(range: part.range, role: .variable))
            case .bare: break
            }
        }
    }

    private func offsets(_ part: WordPart, in lexeme: Lexeme) -> Range<Int> {
        (part.range.lowerBound - lexeme.range.lowerBound)..<(part.range.upperBound - lexeme.range.lowerBound)
    }

    /// The word as the shell would see it, without quotes or backslash escapes (no expansion).
    static func literal(_ lexeme: Lexeme, parts: [WordPart]) -> String {
        let scalars = Array(lexeme.text.unicodeScalars)
        var result = String.UnicodeScalarView()
        for part in parts {
            let local = Array(
                scalars[
                    (part.range.lowerBound - lexeme.range.lowerBound)..<(part.range.upperBound - lexeme.range.lowerBound)
                ])
            switch part.kind {
            case .quoted: result.append(contentsOf: unquoted(local))
            case .bare: result.append(contentsOf: unescaped(local))
            case .variable: result.append(contentsOf: local)
            }
        }
        return String(result)
    }

    private static func unquoted(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard let first = scalars.first, first == "'" || first == "\"" else { return scalars }
        let body = scalars.dropFirst()
        return Array(body.last == first ? body.dropLast() : body)
    }

    private static func unescaped(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        var isEscaped = false
        for scalar in scalars {
            if !isEscaped, scalar == "\\" {
                isEscaped = true
                continue
            }
            isEscaped = false
            result.append(scalar)
        }
        return result
    }
}
