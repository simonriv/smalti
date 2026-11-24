/// One piece of the command line as the highlighter sees it: a word (with its quoted, variable and bare parts), a
/// control operator (`|`, `&&`, `;`, `(`…) or a redirection (`>`, `2>&1`, `&>`…). Ranges count Unicode scalars, as
/// zsh's `region_highlight` does with `MULTIBYTE`; `text` is the raw text, quotes included.
public struct Lexeme: Equatable, Sendable {
    public let kind: LexemeKind
    public let range: Range<Int>
    public let text: String

    public init(kind: LexemeKind, range: Range<Int>, text: String) {
        self.kind = kind
        self.range = range
        self.text = text
    }
}

public enum LexemeKind: Equatable, Sendable {
    case word(parts: [WordPart])
    case controlOperator
    case redirection
}

public struct WordPart: Equatable, Sendable {
    public let kind: WordPartKind
    public let range: Range<Int>

    public init(kind: WordPartKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

public enum WordPartKind: Equatable, Sendable {
    case bare
    case quoted
    case variable
}

/// Splits a command line for highlighting. Unlike `ShellWords` (completion), it keeps quotes, variables and
/// operators, because they are what gets colored. It tolerates a half-typed line: an unterminated quote or `${`
/// runs to the end.
public enum HighlightLexer {
    public static func lexemes(in text: String) -> [Lexeme] {
        var scanner = Scanner(scalars: Array(text.unicodeScalars))
        return scanner.run()
    }
}

private struct Scanner {
    let scalars: [Unicode.Scalar]
    private var offset = 0
    private var lexemes: [Lexeme] = []
    private var parts: [WordPart] = []
    private var wordStart: Int?

    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private static let controlPairs: Set<String> = ["&&", "||", ";;", "|&"]
    private static let controlSingles: Set<Unicode.Scalar> = ["|", "&", ";", "(", ")", "\n"]
    private static let specialParameters: Set<Unicode.Scalar> = ["?", "#", "$", "!", "*", "@", "-"]

    mutating func run() -> [Lexeme] {
        while offset < scalars.count {
            step()
        }
        closeWord()
        return lexemes
    }

    private mutating func step() {
        let scalar = scalars[offset]
        if wordStart == nil, let end = redirectionEnd(at: offset) {
            emit(.redirection, offset..<end)
        } else if scalar == " " || scalar == "\t" {
            closeWord()
            offset += 1
        } else if let end = controlEnd(at: offset) {
            closeWord()
            emit(.controlOperator, offset..<end)
        } else if scalar == "<" || scalar == ">", let end = redirectionEnd(at: offset) {
            closeWord()
            emit(.redirection, offset..<end)
        } else {
            consumeWordPart()
        }
    }

    // MARK: - Operators

    private func controlEnd(at start: Int) -> Int? {
        if start + 1 < scalars.count {
            let pair = String(String.UnicodeScalarView([scalars[start], scalars[start + 1]]))
            if Self.controlPairs.contains(pair) { return start + 2 }
        }
        let scalar = scalars[start]
        if scalar == "&", start + 1 < scalars.count, scalars[start + 1] == ">" { return nil }
        return Self.controlSingles.contains(scalar) ? start + 1 : nil
    }

    /// `[n]>`, `[n]>>`, `[n]>|`, `[n]<`, `<<`, `<<<`, `&>`, `&>>` and `>&n`/`>&-`, starting a word.
    private func redirectionEnd(at start: Int) -> Int? {
        var index = start
        if scalars[index] == "&" {
            index += 1
        } else {
            while index < scalars.count, isDigit(scalars[index]) { index += 1 }
        }
        guard index < scalars.count, scalars[index] == ">" || scalars[index] == "<" else { return nil }
        let direction = scalars[index]
        index += 1
        while index < scalars.count, scalars[index] == direction, index - start < 4 { index += 1 }
        if index < scalars.count, scalars[index] == "|" || scalars[index] == "&" {
            index += 1
            while index < scalars.count, isDigit(scalars[index]) || scalars[index] == "-" { index += 1 }
        }
        return index
    }

    // MARK: - Words

    private mutating func consumeWordPart() {
        if wordStart == nil { wordStart = offset }
        let scalar = scalars[offset]
        let start = offset
        switch scalar {
        case "'":
            offset = closing("'", after: offset + 1)
            add(.quoted, start..<offset)
        case "\"":
            consumeDoubleQuoted()
        case "$" where peek(1) == "'":
            offset = closingEscaped(after: offset + 2)
            add(.quoted, start..<offset)
        case "$":
            if let end = variableEnd(at: offset) {
                offset = end
                add(.variable, start..<end)
            } else {
                offset += 1
                add(.bare, start..<offset)
            }
        case "\\":
            offset = min(offset + 2, scalars.count)
            add(.bare, start..<offset)
        default:
            offset += 1
            add(.bare, start..<offset)
        }
    }

    /// `"…"` with its variables as parts of their own; escapes stay inside the quoted part.
    private mutating func consumeDoubleQuoted() {
        var start = offset
        offset += 1
        while offset < scalars.count, scalars[offset] != "\"" {
            if scalars[offset] == "\\" {
                offset = min(offset + 2, scalars.count)
            } else if scalars[offset] == "$", let end = variableEnd(at: offset) {
                if start < offset { add(.quoted, start..<offset) }
                add(.variable, offset..<end)
                offset = end
                start = offset
            } else {
                offset += 1
            }
        }
        offset = min(offset + 1, scalars.count)
        if start < offset { add(.quoted, start..<offset) }
    }

    private func closing(_ quote: Unicode.Scalar, after start: Int) -> Int {
        var index = start
        while index < scalars.count, scalars[index] != quote { index += 1 }
        return min(index + 1, scalars.count)
    }

    /// The end of `$'…'`, where a backslash escapes the next scalar.
    private func closingEscaped(after start: Int) -> Int {
        var index = start
        while index < scalars.count, scalars[index] != "'" {
            index += scalars[index] == "\\" ? 2 : 1
        }
        return min(index + 1, scalars.count)
    }

    /// `$name`, `${…}`, `$1` and special parameters; `nil` for a lone `$` or `$(`.
    private func variableEnd(at start: Int) -> Int? {
        guard let next = peek(1, from: start) else { return nil }
        if next == "{" { return closing("}", after: start + 2) }
        if isNameStart(next) {
            var index = start + 2
            while index < scalars.count, isNameStart(scalars[index]) || isDigit(scalars[index]) { index += 1 }
            return index
        }
        return isDigit(next) || Self.specialParameters.contains(next) ? start + 2 : nil
    }

    private mutating func add(_ kind: WordPartKind, _ range: Range<Int>) {
        if kind == .bare, let last = parts.last, last.kind == .bare, last.range.upperBound == range.lowerBound {
            parts[parts.count - 1] = WordPart(kind: .bare, range: last.range.lowerBound..<range.upperBound)
        } else {
            parts.append(WordPart(kind: kind, range: range))
        }
    }

    private mutating func closeWord() {
        guard let start = wordStart else { return }
        lexemes.append(Lexeme(kind: .word(parts: parts), range: start..<offset, text: text(start..<offset)))
        parts = []
        wordStart = nil
    }

    private mutating func emit(_ kind: LexemeKind, _ range: Range<Int>) {
        lexemes.append(Lexeme(kind: kind, range: range, text: text(range)))
        offset = range.upperBound
    }

    // MARK: - Scalars

    private func text(_ range: Range<Int>) -> String {
        String(String.UnicodeScalarView(scalars[range]))
    }

    private func peek(_ distance: Int, from start: Int? = nil) -> Unicode.Scalar? {
        let index = (start ?? offset) + distance
        return index < scalars.count ? scalars[index] : nil
    }

    private func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }

    private func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
    }
}
