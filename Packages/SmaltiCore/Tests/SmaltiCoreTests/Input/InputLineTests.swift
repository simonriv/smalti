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
        #expect(tokens.last?.isQuoted == true)
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
}
