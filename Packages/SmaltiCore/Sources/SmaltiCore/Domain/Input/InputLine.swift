/// The line being edited at the shell prompt, as zsh reports it: its text and the cursor.
///
/// The cursor counts Unicode scalars, as zsh's `CURSOR` does with `MULTIBYTE` (`a👍🏽` is 3), never bytes nor
/// grapheme clusters, so positions round-trip with the shell exactly.
public struct InputLine: Equatable, Hashable, Sendable {
    public let text: String
    public let cursor: Int

    public init(text: String, cursor: Int) {
        self.text = text
        self.cursor = min(max(cursor, 0), text.unicodeScalars.count)
    }

    public var isCursorAtEnd: Bool { cursor == text.unicodeScalars.count }

    /// The words of the last simple command before the cursor: what a completion acts on.
    public var currentCommand: [Token] { ShellWords.lastCommand(in: Array(text.unicodeScalars.prefix(cursor))) }

    /// The word that ends at the cursor, or an empty word at the cursor after a separator or a space.
    public var currentWord: Token {
        guard let last = currentCommand.last, last.range.upperBound == cursor else {
            return Token(text: "", range: cursor..<cursor, isQuoted: false)
        }
        return last
    }
}

/// One shell word, without its quotes and escapes. `range` is in Unicode scalars of the line, quotes included.
public struct Token: Equatable, Hashable, Sendable {
    public let text: String
    public let range: Range<Int>
    public let isQuoted: Bool

    public init(text: String, range: Range<Int>, isQuoted: Bool) {
        self.text = text
        self.range = range
        self.isQuoted = isQuoted
    }
}

/// Splits shell input into words the way the prompt user means them: quotes and backslashes join, and `;`, `|`
/// and `&` (single or doubled) outside quotes start a new command. Unterminated quotes run to the end.
enum ShellWords {
    static func lastCommand(in scalars: [Unicode.Scalar]) -> [Token] {
        var splitter = Splitter()
        for (offset, scalar) in scalars.enumerated() { splitter.consume(scalar, at: offset) }
        return splitter.finish(at: scalars.count)
    }

    private struct Splitter {
        private var tokens: [Token] = []
        private var word = String.UnicodeScalarView()
        private var start: Int?
        private var quote: Unicode.Scalar?
        private var isEscaped = false
        private var wasQuoted = false

        mutating func consume(_ scalar: Unicode.Scalar, at offset: Int) {
            if isEscaped {
                append(scalar, at: offset)
                isEscaped = false
            } else if let open = quote {
                consumeQuoted(scalar, open: open, at: offset)
            } else {
                consumeBare(scalar, at: offset)
            }
        }

        mutating func finish(at end: Int) -> [Token] {
            closeWord(at: end)
            return tokens
        }

        private mutating func consumeQuoted(_ scalar: Unicode.Scalar, open: Unicode.Scalar, at offset: Int) {
            if scalar == open {
                quote = nil
            } else if scalar == "\\" && open == "\"" {
                isEscaped = true
            } else {
                append(scalar, at: offset)
            }
        }

        private mutating func consumeBare(_ scalar: Unicode.Scalar, at offset: Int) {
            switch scalar {
            case "\\":
                markStart(at: offset)
                isEscaped = true
            case "'", "\"":
                markStart(at: offset)
                quote = scalar
                wasQuoted = true
            case ";", "|", "&":
                closeWord(at: offset)
                tokens.removeAll()
            case _ where scalar.properties.isWhitespace:
                closeWord(at: offset)
            default:
                append(scalar, at: offset)
            }
        }

        private mutating func append(_ scalar: Unicode.Scalar, at offset: Int) {
            markStart(at: offset)
            word.append(scalar)
        }

        private mutating func markStart(at offset: Int) {
            if start == nil { start = offset }
        }

        private mutating func closeWord(at end: Int) {
            guard let begin = start else { return }
            tokens.append(Token(text: String(word), range: begin..<end, isQuoted: wasQuoted))
            word = String.UnicodeScalarView()
            start = nil
            wasQuoted = false
        }
    }
}
