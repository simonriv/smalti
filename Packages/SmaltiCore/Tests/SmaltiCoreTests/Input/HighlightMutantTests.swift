import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Review 1 mutation: each test kills a surviving mutant of the highlighter (lexer, roles, use case and defaults).
@Suite("Highlight · mutation 1")
struct HighlightMutantTests {
    private func lexemes(_ text: String) -> [Lexeme] { HighlightLexer.lexemes(in: text) }

    private func kinds(_ text: String) -> [String] {
        lexemes(text).map { lexeme in
            switch lexeme.kind {
            case .word: "w:\(lexeme.text)"
            case .controlOperator: "c:\(lexeme.text)"
            case .redirection: "r:\(lexeme.text)"
            case .arithmetic: "a:\(lexeme.text)"
            }
        }
    }

    private func plan(_ text: String, specs: [CompletionSpec] = []) -> HighlightPlan {
        LineHighlighter.plan(for: text) { name in specs.first { $0.name.contains(name) } }
    }

    private func spans(_ text: String, _ role: HighlightRole, specs: [CompletionSpec] = []) -> [Range<Int>] {
        plan(text, specs: specs).spans.filter { $0.role == role }.map(\.range)
    }

    private static let git = CompletionSpec(
        name: ["git"], subcommands: [CompletionSpec(name: ["checkout"])],
        options: [OptionSpec(names: ["-C"], args: [ArgSpec(name: "path")])])

    // MARK: - Lexer

    @Test func redirectionInsideAWordEndsTheWord() {
        #expect(kinds("a>b") == ["w:a", "r:>", "w:b"])
        #expect(kinds("a<b") == ["w:a", "r:<", "w:b"])
        #expect(kinds("a&>b") == ["w:a", "r:&>", "w:b"])
    }

    @Test func closingDescriptorRedirections() {
        #expect(kinds("x >&- y") == ["w:x", "r:>&-", "w:y"])
        #expect(kinds("x 2>&12 y") == ["w:x", "r:2>&12", "w:y"])
    }

    @Test func commandSubstitutionIsNotArithmetic() {
        #expect(kinds("echo $(ls)") == ["w:echo", "w:$", "c:(", "w:ls", "c:)"])
    }

    @Test func nestedArithmeticExpansion() {
        #expect(lexemes("echo $(((1)+2))y")[1].range == 5..<16)
    }

    @Test func arithmeticExpansionEndsAtItsClosing() {
        #expect(kinds("echo $(((1)+2)) y") == ["w:echo", "w:$(((1)+2))", "w:y"])
    }

    @Test func arithmeticCommandClosingRightAfterWord() {
        #expect(kinds("(( x)) y") == ["a:(( x))", "w:y"])
    }

    @Test func arithmeticEndingInOneParenthesisRunsToEnd() {
        #expect(kinds("(( x)") == ["a:(( x)"])
    }

    @Test func nestedArithmeticCommand() {
        #expect(kinds("(( (a) )) x") == ["a:(( (a) ))", "w:x"])
    }

    @Test func escapedQuoteInsideDoubleQuotes() {
        #expect(kinds("\"a\\\"b\" c") == ["w:\"a\\\"b\"", "w:c"])
    }

    @Test func escapedQuoteInsideDollarQuotes() {
        #expect(kinds("$'a\\'b' c") == ["w:$'a\\'b'", "w:c"])
    }

    // MARK: - Roles

    @Test func redirectionTargetStartingWithDashIsNotOption() {
        let result = plan("ls > -out")

        #expect(spans("ls > -out", .option).isEmpty)
        #expect(result.pathCandidates.map(\.word) == ["-out"])
    }

    @Test func wordAfterRedirectionTargetIsOptionAgain() {
        #expect(spans("ls > a -b", .option) == [7..<9])
    }

    @Test func variableCommandAfterPipeHasNoStaleSpec() {
        #expect(spans("git | $X checkout", .subcommand, specs: [Self.git]).isEmpty)
    }

    @Test func positionalsResetAfterPipe() {
        #expect(spans("git x | git checkout", .subcommand, specs: [Self.git]) == [12..<20])
    }

    @Test func optionArgumentsResetAfterPipe() {
        #expect(spans("git -C | git checkout", .subcommand, specs: [Self.git]) == [13..<21])
    }

    @Test func precommandResetAfterPipe() {
        #expect(spans("sudo | -x", .command) == [0..<4, 7..<9])
    }

    @Test func precommandValueResetAfterPipe() {
        #expect(spans("sudo -u | ls", .command) == [0..<4, 10..<12])
    }

    @Test func wordAfterArithmeticIsNotCommand() {
        #expect(spans("(( x )) y", .command).isEmpty)
    }

    @Test func precommandWithoutValueOptionsKeepsCommand() {
        #expect(spans("time -p ls", .command) == [0..<4, 8..<10])
    }

    @Test func assignmentValuePartsAreColored() {
        #expect(spans("A=\"x\" cmd", .string) == [2..<5])
    }

    @Test(arguments: [
        ("A1=x make", [5..<9], [0..<2]), ("1A=x y", [0..<4], []), ("a-b=x y", [0..<5], []),
        ("_X=1 make", [5..<9], [0..<2]), ("ab=1 make", [5..<9], [0..<2]),
    ])
    func assignmentNames(_ text: String, _ commands: [Range<Int>], _ variables: [Range<Int>]) {
        #expect(spans(text, .command) == commands)
        #expect(spans(text, .variable) == variables)
    }

    @Test func doubleQuotedCommandIsUnquoted() {
        #expect(plan("\"ls\" x").commandsWithoutSpec == ["ls"])
    }

    @Test(arguments: [("ls \\ab", "ab"), ("ls a\\\\b", "a\\b"), ("ls a\\ b\\ c", "a b c")])
    func escapesInPathCandidates(_ text: String, _ word: String) {
        #expect(plan(text).pathCandidates.map(\.word) == [word])
    }

    // MARK: - Use case and defaults

    @Test func pathSpanSitsBetweenSpansByStart() async {
        let subject = HighlightLine(
            paths: InMemoryPathFacts(kinds: ["/w/a": .file]), completions: FakeCompletionProvider())

        let answer = await subject.firstAnswer(
            InputLine(text: "cat a -x", cursor: 8), directory: "/w", home: "/h")

        #expect(answer.spans.map(\.role) == [.command, .path, .option])
    }

    @Test func expiredPathsArePruned() async {
        final class Now: @unchecked Sendable { var date = Date(timeIntervalSince1970: 0) }
        let now = Now()
        let subject = HighlightLine(
            paths: InMemoryPathFacts(), completions: FakeCompletionProvider(),
            timing: HighlightTiming(budget: .milliseconds(50)) { now.date })
        _ = await subject.firstAnswer(InputLine(text: "ls a b", cursor: 6), directory: "/w", home: "/h")
        now.date += 3

        _ = await subject.firstAnswer(InputLine(text: "ls c", cursor: 4), directory: "/w", home: "/h")

        #expect(await subject.cachedPathCount == 1)
    }

    @Test func inputHighlightingDefaultsOn() {
        #expect(InputSettings.standard.isHighlighting)
    }

    @Test func argIsNotCommandByDefault() {
        #expect(!ArgSpec().isCommand)
    }

    @MainActor
    @Test func promptEnvironmentHighlightsByDefault() {
        let render = RenderPrompt(
            facts: FakePromptFacts(),
            environment: PromptEnvironment(
                settings: { (PromptConfig.standard, ThemeCatalog.apply(.obsidian)) }, agents: { _ in WaitingAgents() },
                workspace: { _ in nil }, home: "/h", now: { Date(timeIntervalSince1970: 0) }))

        #expect(render.styleMessages().last != .highlightStyle(nil))
    }
}
