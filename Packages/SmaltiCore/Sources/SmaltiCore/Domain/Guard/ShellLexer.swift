/// One simple command as the lexer saw it: its words (quotes removed, `~` and `$HOME` expanded), its redirection
/// targets, the source text, and the texts of the `$( … )` and backquote substitutions inside it.
struct LexedSegment: Equatable {
    var words: [String] = []
    var redirections: [String] = []
    var substitutions: [String] = []
    /// The bodies of its here-documents (`<<EOF … EOF`), never lexed as commands.
    var heredocs: [String] = []
    var rawText = ""
}

/// A tolerant, single-pass shell lexer (spec F7.5): it never fails. An unterminated quote ends at the end of the
/// text; anything it does not understand becomes part of a word. It is not a shell: it only needs to see the words a
/// guard rule compares, the way zsh or bash would split them.
struct ShellLexer {
    private let characters: [Character]
    private let home: String
    private var index = 0
    private var segments: [LexedSegment] = []
    private var segment = LexedSegment()
    private var segmentStart = 0
    private var word: String?
    private var pendingRedirection = false
    /// After `<<` or `<<-`: the next word is a here-document delimiter.
    private var pendingDelimiter: Bool?
    /// Here-documents whose body starts after the next newline: delimiter, `<<-`, and the segment they belong to.
    private var heredocs: [(delimiter: String, stripsTabs: Bool, segment: Int)] = []

    init(_ text: String, home: String) {
        // `\r\n` is one Swift `Character`: folded to `\n` so it separates commands as a shell does (review 1).
        characters = Array(text.replacing("\r\n", with: "\n").replacing("\r", with: "\n"))
        self.home = home
    }

    static func segments(of text: String, home: String) -> [LexedSegment] {
        var lexer = ShellLexer(text, home: home)
        return lexer.run()
    }

    private mutating func run() -> [LexedSegment] {
        while index < characters.count { step() }
        endSegment(at: characters.count)
        return segments
    }

    private mutating func step() {
        let character = characters[index]
        switch character {
        case " ", "\t": endWord()
        case "&" where next == ">": redirection()
        case "\n":
            separator(character)
            readHeredocBodies()
        case ";", "&", "|", "(", ")": separator(character)
        case "<", ">": redirection()
        case "'": singleQuoted()
        case "\"": doubleQuoted()
        case "\\": escaped()
        case "$": dollar(inDoubleQuotes: false)
        case "`": backquoted()
        case "#" where word == nil: comment()
        case "~" where word == nil && isHomeTilde(): appendToWord(home)
        default: appendToWord(String(character))
        }
        index += 1
    }

    // MARK: - Words and segments

    private mutating func appendToWord(_ text: String) {
        word = (word ?? "") + text
    }

    private mutating func endWord() {
        guard let finished = word else { return }
        word = nil
        if let stripsTabs = pendingDelimiter {
            pendingDelimiter = nil
            heredocs.append((finished, stripsTabs, segments.count))
        } else if pendingRedirection {
            pendingRedirection = false
            // `2>&1` duplicates a descriptor: there is no file.
            if !finished.hasPrefix("&") { segment.redirections.append(finished) }
        } else {
            segment.words.append(finished)
        }
    }

    private mutating func separator(_ character: Character) {
        // `>&` and `&>` are redirections, handled there; a lone `&` after a redirection operator never reaches here.
        endSegment(at: index)
        if (character == "&" || character == "|") && next == character { index += 1 }
        segmentStart = index + 1
    }

    private mutating func endSegment(at end: Int) {
        endWord()
        pendingRedirection = false
        let source = segmentStart < end ? String(characters[segmentStart..<end]) : ""
        segment.rawText = Self.trimmed(source)
        if !segment.words.isEmpty || !segment.redirections.isEmpty || !segment.substitutions.isEmpty {
            segments.append(segment)
        }
        segment = LexedSegment()
    }

    private static func trimmed(_ text: String) -> String {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" }
        return String(text.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    private var next: Character? { index + 1 < characters.count ? characters[index + 1] : nil }

    // MARK: - Redirections

    /// `<`, `>`, `>>`, `<<`, `<<<`, `>&`, `&>`, `>|`, with an optional descriptor number before it.
    private mutating func redirection() {
        if let current = word, current.allSatisfy(\.isNumber) { word = nil } else { endWord() }
        var operation = String(characters[index])
        while let following = next, "<>|".contains(following) {
            index += 1
            operation.append(following)
        }
        if operation == "<<" {
            heredocOperator()
            return
        }
        if next == "&", index + 2 < characters.count, isDescriptor(characters[index + 2]) {
            index += 1
            while let following = next, isDescriptor(following) { index += 1 }
            return
        }
        if next == "&" { index += 1 }
        pendingRedirection = true
    }

    /// `<<DELIM` or `<<-DELIM` (tabs before the closing line are ignored).
    private mutating func heredocOperator() {
        let stripsTabs = next == "-"
        if stripsTabs { index += 1 }
        pendingDelimiter = stripsTabs
    }

    /// After a newline: each pending here-document takes the following lines up to its delimiter, as data.
    private mutating func readHeredocBodies() {
        let pending = heredocs
        heredocs = []
        for heredoc in pending {
            var lines: [String] = []
            while index + 1 < characters.count {
                let start = index + 1
                var end = start
                while end < characters.count, characters[end] != "\n" { end += 1 }
                let line = String(characters[start..<end])
                index = end
                let closing = heredoc.stripsTabs ? String(line.drop { $0 == "\t" }) : line
                if closing == heredoc.delimiter { break }
                lines.append(line)
            }
            if heredoc.segment < segments.count {
                segments[heredoc.segment].heredocs.append(lines.joined(separator: "\n"))
            }
        }
        segmentStart = index + 1
    }

    private func isDescriptor(_ character: Character) -> Bool {
        character.isNumber || character == "-"
    }

    // MARK: - Quotes, escapes and comments

    private mutating func singleQuoted() {
        var text = ""
        index += 1
        while index < characters.count, characters[index] != "'" {
            text.append(characters[index])
            index += 1
        }
        appendToWord(text)
    }

    private mutating func doubleQuoted() {
        appendToWord("")
        index += 1
        while index < characters.count, characters[index] != "\"" {
            doubleQuotedStep()
            index += 1
        }
    }

    private mutating func doubleQuotedStep() {
        let character = characters[index]
        switch character {
        case "\\":
            if let following = next, "$`\"\\\n".contains(following) {
                index += 1
                if following != "\n" { appendToWord(String(following)) }
            } else {
                appendToWord("\\")
            }
        case "$": dollar(inDoubleQuotes: true)
        case "`": backquoted()
        default: appendToWord(String(character))
        }
    }

    private mutating func escaped() {
        guard let following = next else { return }
        index += 1
        if following != "\n" { appendToWord(String(following)) }
    }

    private mutating func comment() {
        while let following = next, following != "\n" { index += 1 }
    }

    private func isHomeTilde() -> Bool {
        guard let following = next else { return true }
        return following == "/" || following == " " || following == "\t" || following == "\n" || following == ";"
    }

    // MARK: - Expansions

    /// `$HOME` and `${HOME}` expand; `$( … )` is a substitution; any other parameter stays as written.
    private mutating func dollar(inDoubleQuotes: Bool) {
        if next == "(" {
            index += 1
            substitution(closing: ")")
        } else if next == "'" && !inDoubleQuotes {
            ansiCQuoted()
        } else if matches("{HOME}") {
            index += 6
            appendToWord(home)
        } else if matches("HOME"), !isNameCharacter(at: index + 5) {
            index += 4
            appendToWord(home)
        } else {
            appendToWord("$")
        }
    }

    /// `$'…'`: a quote with C escapes (`\n`, `\t`, `\xHH`, `\NNN`), so `$'.env'` is `.env` (review 1).
    private mutating func ansiCQuoted() {
        index += 2
        var text = ""
        while index < characters.count, characters[index] != "'" {
            if characters[index] == "\\", let following = next {
                index += 1
                text.append(cEscape(following))
            } else {
                text.append(characters[index])
            }
            index += 1
        }
        appendToWord(text)
    }

    private mutating func cEscape(_ character: Character) -> String {
        switch character {
        case "n": return "\n"
        case "t": return "\t"
        case "x": return numericEscape(radix: 16, maximumDigits: 2)
        case "0"..."7":
            index -= 1
            return numericEscape(radix: 8, maximumDigits: 3)
        default: return String(character)
        }
    }

    /// The digits after the current index as one character; the index ends on the last digit.
    private mutating func numericEscape(radix: Int, maximumDigits: Int) -> String {
        var digits = ""
        while digits.count < maximumDigits, let following = next, following.isHexDigit,
            Int(String(following), radix: radix) != nil
        {
            digits.append(following)
            index += 1
        }
        guard let value = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(value) else { return "" }
        return String(Character(scalar))
    }

    private mutating func backquoted() {
        substitution(closing: "`")
    }

    /// Collects the text up to the matching close (nested parentheses counted) as a substitution, and leaves an
    /// empty word part: the guard reads the substitution's own commands, not its output.
    private mutating func substitution(closing: Character) {
        var depth = 1
        var text = ""
        index += 1
        while index < characters.count {
            let character = characters[index]
            if closing == ")" && character == "(" { depth += 1 }
            if character == closing {
                depth -= 1
                if depth == 0 { break }
            }
            text.append(character)
            index += 1
        }
        segment.substitutions.append(text)
        appendToWord("")
    }

    private func matches(_ literal: String) -> Bool {
        let start = index + 1
        let end = start + literal.count
        guard end <= characters.count else { return false }
        return String(characters[start..<end]) == literal
    }

    private func isNameCharacter(at position: Int) -> Bool {
        guard position < characters.count else { return false }
        let character = characters[position]
        return character.isLetter || character.isNumber || character == "_"
    }
}
