import SmaltiCore
import Testing

@Suite("InputLine")
struct InputLineTests {
    private func line(_ text: String) -> InputLine {
        InputLine(text: text, cursor: text.unicodeScalars.count)
    }

    @Test func tokensSplitOnWhitespace() {
        let tokens = line("git  checkout main").currentCommand

        #expect(tokens.map(\.text) == ["git", "checkout", "main"])
    }

    @Test func quotedWordKeepsSpaces() {
        let tokens = line("git commit -m \"a b\"").currentCommand

        #expect(tokens.map(\.text) == ["git", "commit", "-m", "a b"])
        #expect(tokens.last?.openingQuote == "\"")
    }

    @Test func escapedSpaceJoinsWord() {
        let tokens = line("cd My\\ Folder").currentCommand

        #expect(tokens.map(\.text) == ["cd", "My Folder"])
    }

    @Test func currentCommandStartsAfterPipeAndAnd() {
        let tokens = line("ls | grep x && git ch").currentCommand

        #expect(tokens.map(\.text) == ["git", "ch"])
    }

    @Test func currentCommandStartsAfterSemicolonAndOr() {
        #expect(line("make; npm r").currentCommand.map(\.text) == ["npm", "r"])
        #expect(line("false || swift te").currentCommand.map(\.text) == ["swift", "te"])
    }

    @Test func unterminatedQuoteIsOneToken() {
        let tokens = line("echo \"a b").currentCommand

        #expect(tokens.map(\.text) == ["echo", "a b"])
    }

    @Test func separatorInsideQuotesDoesNotSplitCommands() {
        let tokens = line("echo 'a|b' x").currentCommand

        #expect(tokens.map(\.text) == ["echo", "a|b", "x"])
    }

    @Test func onlyTextBeforeTheCursorCounts() {
        let tokens = InputLine(text: "git ch && ls", cursor: 6).currentCommand

        #expect(tokens.map(\.text) == ["git", "ch"])
    }

    @Test func currentWordIsTheTokenEndingAtTheCursor() {
        let word = line("git ch").currentWord

        #expect(word.text == "ch")
        #expect(word.range == 4..<6)
    }

    @Test func currentWordIsEmptyAfterTrailingSpace() {
        let word = line("git ").currentWord

        #expect(word.text.isEmpty)
        #expect(word.range == 4..<4)
    }

    @Test func cursorCountsUnicodeScalarsLikeZsh() {
        let text = "echo canción a👍🏽"
        let line = InputLine(text: text, cursor: 16)

        #expect(line.isCursorAtEnd)
        #expect(line.currentWord.text == "a👍🏽")
        #expect(line.currentWord.range == 13..<16)
    }

    @Test func cursorBeforeEndIsNotAtEnd() {
        #expect(!InputLine(text: "git", cursor: 1).isCursorAtEnd)
    }

    @Test func cursorOutOfBoundsIsClamped() {
        #expect(InputLine(text: "ls", cursor: 9).cursor == 2)
        #expect(InputLine(text: "ls", cursor: -3).cursor == 0)
    }

    @Test func emptyLineHasNoCommand() {
        #expect(line("").currentCommand.isEmpty)
        #expect(line("   ").currentCommand.isEmpty)
    }

    // Review I3: the word containing the cursor is the whole word, and only its part before the cursor is typed.
    @Test func currentWordCoversTheWholeWordAroundTheCursor() {
        let line = InputLine(text: "git chekout main", cursor: 7)

        #expect(line.currentWord.range == 4..<11)
        #expect(line.wordBeforeCursor == "che")
    }

    @Test func cursorAtTheStartOfAWordStartsAnEmptyWord() {
        let line = InputLine(text: "git checkout", cursor: 4)

        #expect(line.currentWord.range == 4..<4)
        #expect(line.wordBeforeCursor.isEmpty)
    }

    @Test func openingQuoteIsRemembered() {
        #expect(line("cat \"My Fi").currentWord.openingQuote == "\"")
        #expect(line("cat 'My Fi").currentWord.openingQuote == "'")
        #expect(line("cat My").currentWord.openingQuote == nil)
    }

    // Review m5: zsh's word and command rules.
    @Test func newlineSeparatesCommands() {
        #expect(line("ls\ngit ch").currentCommand.map(\.text) == ["git", "ch"])
    }

    @Test func backslashNewlineContinuesTheLine() {
        #expect(line("git \\\ncommit").currentCommand.map(\.text) == ["git", "commit"])
    }

    @Test func ampersandInRedirectionDoesNotSplit() {
        #expect(line("git log 2>&1 --on").currentCommand.map(\.text) == ["git", "log", "2>&1", "--on"])
        #expect(line("make &>/dev/null bu").currentCommand.map(\.text) == ["make", "&>/dev/null", "bu"])
    }

    @Test func nonBreakingSpaceStaysInsideTheWord() {
        #expect(line("echo a\u{00A0}b").currentCommand.map(\.text) == ["echo", "a\u{00A0}b"])
    }

    // Mutation survivors (F4 close): escapes end after one character, `\"` only escapes inside double quotes,
    // a trailing `&`, and the opening quote of one word never leaks into the next.
    @Test func escapeCoversOnlyTheNextCharacter() {
        #expect(line("echo a\\ b c").currentCommand.map(\.text) == ["echo", "a b", "c"])
    }

    @Test func backslashEscapesAQuoteInsideDoubleQuotes() {
        #expect(line("echo \"a\\\"b\" x").currentCommand.map(\.text) == ["echo", "a\"b", "x"])
    }

    @Test func backslashIsLiteralInsideSingleQuotes() {
        #expect(line("echo 'a\\b' x").currentCommand.map(\.text) == ["echo", "a\\b", "x"])
    }

    @Test func trailingAmpersandEndsTheCommand() {
        #expect(line("sleep 1 &").currentCommand.map(\.text) == [])
    }

    @Test func openingQuoteBelongsToItsOwnWord() {
        let tokens = line("echo 'a' b").currentCommand

        #expect(tokens.map(\.openingQuote) == [nil, "'", nil])
    }
}
