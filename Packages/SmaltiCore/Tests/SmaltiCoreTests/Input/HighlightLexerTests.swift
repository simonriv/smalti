import SmaltiCore
import Testing

@Suite("HighlightLexer")
struct HighlightLexerTests {
    private func words(_ lexemes: [Lexeme]) -> [String] {
        lexemes.compactMap { if case .word = $0.kind { $0.text } else { nil } }
    }

    private func parts(_ lexeme: Lexeme) -> [WordPart] {
        if case .word(let parts) = lexeme.kind { return parts }
        return []
    }

    @Test func splitsWordsAndControlOperators() {
        let lexemes = HighlightLexer.lexemes(in: "git add . && ls | wc")

        #expect(words(lexemes) == ["git", "add", ".", "ls", "wc"])
        let operators = lexemes.filter { $0.kind == .controlOperator }
        #expect(operators.map(\.range) == [10..<12, 16..<17])
        #expect(operators.map(\.text) == ["&&", "|"])
    }

    @Test func redirectionsAreTheirOwnLexeme() {
        let lexemes = HighlightLexer.lexemes(in: "ls > out 2>&1")

        let redirections = lexemes.filter { $0.kind == .redirection }
        #expect(redirections.map(\.range) == [3..<4, 9..<13])
        #expect(words(lexemes) == ["ls", "out"])
    }

    @Test func appendAndAmpersandRedirections() {
        let lexemes = HighlightLexer.lexemes(in: "a >> b &> c")

        #expect(lexemes.filter { $0.kind == .redirection }.map(\.text) == [">>", "&>"])
        #expect(words(lexemes) == ["a", "b", "c"])
    }

    @Test func quotedPartsKeepTheirQuotes() {
        let lexemes = HighlightLexer.lexemes(in: "echo \"a $HOME\" 'b'")

        #expect(
            parts(lexemes[1]) == [
                WordPart(kind: .quoted, range: 5..<8), WordPart(kind: .variable, range: 8..<13),
                WordPart(kind: .quoted, range: 13..<14),
            ])
        #expect(parts(lexemes[2]) == [WordPart(kind: .quoted, range: 15..<18)])
        #expect(lexemes[1].text == "\"a $HOME\"")
    }

    @Test func dollarSingleQuoteIsQuoted() {
        let lexemes = HighlightLexer.lexemes(in: "$'a\\n'")

        #expect(parts(lexemes[0]) == [WordPart(kind: .quoted, range: 0..<6)])
    }

    @Test(arguments: ["$x", "${x:-y}", "$1", "$?", "$#", "$_long_name9"])
    func variableForms(_ form: String) {
        let lexemes = HighlightLexer.lexemes(in: form)

        #expect(parts(lexemes[0]) == [WordPart(kind: .variable, range: 0..<form.unicodeScalars.count)])
    }

    @Test func variableInsideBareWord() {
        let lexemes = HighlightLexer.lexemes(in: "a$x/b")

        #expect(
            parts(lexemes[0]) == [
                WordPart(kind: .bare, range: 0..<1), WordPart(kind: .variable, range: 1..<3),
                WordPart(kind: .bare, range: 3..<5),
            ])
    }

    @Test func loneDollarIsBare() {
        let lexemes = HighlightLexer.lexemes(in: "a $ b")

        #expect(parts(lexemes[1]) == [WordPart(kind: .bare, range: 2..<3)])
    }

    @Test func unterminatedQuoteRunsToEnd() {
        let lexemes = HighlightLexer.lexemes(in: "echo \"abc")

        #expect(parts(lexemes[1]) == [WordPart(kind: .quoted, range: 5..<9)])
    }

    @Test func escapedSpaceStaysInWord() {
        let lexemes = HighlightLexer.lexemes(in: "ls a\\ b")

        #expect(lexemes[1].range == 3..<7)
        #expect(lexemes.count == 2)
    }

    @Test func emojiShiftsRangesByScalars() {
        let lexemes = HighlightLexer.lexemes(in: "echo 👍🏽 x")

        #expect(lexemes.last?.range == 8..<9)
    }

    @Test func parenthesesAndSemicolonsAreControl() {
        let lexemes = HighlightLexer.lexemes(in: "(a;b)")

        #expect(lexemes.filter { $0.kind == .controlOperator }.map(\.text) == ["(", ";", ")"])
    }

    @Test func emptyAndSingleCharacter() {
        #expect(HighlightLexer.lexemes(in: "").isEmpty)
        #expect(HighlightLexer.lexemes(in: "l").map(\.range) == [0..<1])
    }

    @Test func digitWordIsNotRedirection() {
        let lexemes = HighlightLexer.lexemes(in: "sleep 2")

        #expect(words(lexemes) == ["sleep", "2"])
    }
}
