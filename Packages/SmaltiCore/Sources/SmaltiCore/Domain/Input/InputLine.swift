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

    /// The words of the simple command at the cursor, up to the cursor: what a completion walks. The last one is
    /// cut at the cursor when the cursor is inside it.
    public var currentCommand: [Token] { ShellWords.command(in: scalars, upTo: cursor).tokens }

    /// The whole word around the cursor (what a completion replaces), or an empty word at the cursor when the
    /// cursor is not inside or at the end of one.
    public var currentWord: Token {
        let tokens = ShellWords.command(in: scalars, upTo: scalars.count, stoppingAfter: cursor).tokens
        return tokens.first { $0.range.lowerBound < cursor && cursor <= $0.range.upperBound }
            ?? Token(text: "", range: cursor..<cursor, openingQuote: nil)
    }

    /// The current word's text before the cursor, without quotes or escapes: what was typed of it.
    public var wordBeforeCursor: String {
        guard let last = currentCommand.last, last.range.upperBound == cursor, last.range.lowerBound < cursor else {
            return ""
        }
        return last.text
    }

    private var scalars: [Unicode.Scalar] { Array(text.unicodeScalars) }
}

/// One shell word, without its quotes and escapes. `range` is in Unicode scalars of the line, quotes included.
public struct Token: Equatable, Hashable, Sendable {
    public let text: String
    public let range: Range<Int>
    /// The quote the word starts with (`"` or `'`), which a completion keeps and closes.
    public let openingQuote: Character?

    public init(text: String, range: Range<Int>, openingQuote: Character? = nil) {
        self.text = text
        self.range = range
        self.openingQuote = openingQuote
    }
}

/// Splits shell input into words as zsh does for the prompt user: quotes and backslashes join; only space, tab and
/// newline separate words (a no-break space stays inside); `;`, `|`, `&` and newline outside quotes start a new
/// command, except `&` in a redirection (`2>&1`, `&>`); backslash-newline continues the line. Unterminated quotes
/// run to the end.
enum ShellWords {
    struct Command {
        let tokens: [Token]
    }

    /// Every simple command of `text` (split at `;`, `|`, `&`, `&&`, `||` and newlines), empty ones left out.
    static func commands(in text: String) -> [[Token]] {
        let scalars = Array(text.unicodeScalars)
        var splitter = Splitter(scalars: scalars, stop: scalars.count)
        for offset in scalars.indices { splitter.consume(at: offset) }
        return splitter.finishAll(at: scalars.count)
    }

    /// The command that contains `limit` (or `stoppingAfter`, when given), with its words cut at `limit`.
    static func command(in scalars: [Unicode.Scalar], upTo limit: Int, stoppingAfter stop: Int? = nil) -> Command {
        var splitter = Splitter(scalars: scalars, stop: stop ?? limit)
        for offset in 0..<limit where !splitter.isDone { splitter.consume(at: offset) }
        return Command(tokens: splitter.finish(at: limit))
    }

    private struct Splitter {
        let scalars: [Unicode.Scalar]
        let stop: Int
        private(set) var isDone = false
        private var tokens: [Token] = []
        /// The commands before the current one, kept only for `finishAll`.
        private var completed: [[Token]] = []
        private var word = String.UnicodeScalarView()
        private var start: Int?
        private var quote: Unicode.Scalar?
        private var openingQuote: Character?
        private var isEscaped = false

        init(scalars: [Unicode.Scalar], stop: Int) {
            self.scalars = scalars
            self.stop = stop
        }

        mutating func consume(at offset: Int) {
            let scalar = scalars[offset]
            if isEscaped {
                isEscaped = false
                if scalar != "\n" { append(scalar, at: offset) }
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

        mutating func finishAll(at end: Int) -> [[Token]] {
            closeWord(at: end)
            return (completed + [tokens]).filter { !$0.isEmpty }
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
                if start == nil { openingQuote = Character(scalar) }
                markStart(at: offset)
                quote = scalar
            case "&" where isRedirection(at: offset):
                append(scalar, at: offset)
            case ";", "|", "&", "\n":
                separate(at: offset)
            case " ", "\t":
                closeWord(at: offset)
            default:
                append(scalar, at: offset)
            }
        }

        /// `&` right after `>` or `<` (`2>&1`) or right before `>` (`&>file`) redirects; it does not separate.
        private func isRedirection(at offset: Int) -> Bool {
            let previous = offset > 0 ? scalars[offset - 1] : nil
            let next = offset + 1 < scalars.count ? scalars[offset + 1] : nil
            return previous == ">" || previous == "<" || next == ">"
        }

        /// A separator past `stop` ends the command that contains `stop`; one before it starts a new command.
        private mutating func separate(at offset: Int) {
            if offset >= stop {
                closeWord(at: offset)
                isDone = true
                return
            }
            closeWord(at: offset)
            completed.append(tokens)
            tokens.removeAll()
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
            tokens.append(
                Token(text: String(word), range: begin..<end, openingQuote: openingQuote))
            word = String.UnicodeScalarView()
            start = nil
            openingQuote = nil
        }
    }
}
