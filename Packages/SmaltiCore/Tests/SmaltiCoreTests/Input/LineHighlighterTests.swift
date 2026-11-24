import SmaltiCore
import Testing

@Suite("LineHighlighter")
struct LineHighlighterTests {
    private static let git = CompletionSpec(
        name: ["git"],
        subcommands: [
            CompletionSpec(name: ["checkout"]),
            CompletionSpec(name: ["remote"], subcommands: [CompletionSpec(name: ["add"])]),
            CompletionSpec(name: ["co", "commit"]),
        ],
        options: [OptionSpec(names: ["-C"], args: [ArgSpec(name: "path")])])
    private static let xargs = CompletionSpec(name: ["xargs"], args: [ArgSpec(name: "command", isCommand: true)])

    private func plan(_ text: String, specs: [CompletionSpec] = []) -> HighlightPlan {
        LineHighlighter.plan(for: text) { name in specs.first { $0.name.contains(name) } }
    }

    private func spans(_ text: String, _ role: HighlightRole, specs: [CompletionSpec] = []) -> [Range<Int>] {
        plan(text, specs: specs).spans.filter { $0.role == role }.map(\.range)
    }

    @Test func firstWordIsCommand() {
        let result = plan("git status")

        #expect(result.spans == [HighlightSpan(range: 0..<3, role: .command)])
    }

    @Test func commandAfterEachControlOperator() {
        let text = "a | b && c; (d)"

        #expect(spans(text, .command) == [0..<1, 4..<5, 9..<10, 13..<14])
        #expect(spans(text, .operator) == [2..<3, 6..<8, 10..<11, 12..<13, 14..<15])
    }

    @Test func precommandsShiftCommandPosition() {
        let text = "sudo -E env A=1 nohup time git log"

        #expect(spans(text, .command) == [0..<4, 8..<11, 16..<21, 22..<26, 27..<30])
        #expect(spans(text, .option) == [5..<7])
        #expect(spans(text, .variable) == [12..<13])
    }

    @Test func leadingAssignmentIsVariableNotCommand() {
        let text = "FOO=1 make"

        #expect(spans(text, .variable) == [0..<3])
        #expect(spans(text, .command) == [6..<10])
    }

    @Test func subcommandsFollowSpecInOrder() {
        let text = "git remote add x"

        #expect(spans(text, .subcommand, specs: [Self.git]) == [4..<10, 11..<14])
        #expect(plan(text, specs: [Self.git]).spans.count == 3)
    }

    @Test func subcommandAfterOptionStillCounts() {
        #expect(spans("git -C x checkout", .subcommand, specs: [Self.git]) == [9..<17])
    }

    @Test func subcommandAliasNames() {
        #expect(spans("git co", .subcommand, specs: [Self.git]) == [4..<6])
    }

    @Test func wordAfterPositionalIsNotSubcommand() {
        #expect(spans("git x checkout", .subcommand, specs: [Self.git]).isEmpty)
    }

    @Test func isCommandArgumentStartsNewCommand() {
        let text = "xargs grep -n"

        #expect(spans(text, .command, specs: [Self.xargs]) == [0..<5, 6..<10])
        #expect(spans(text, .option, specs: [Self.xargs]) == [11..<13])
    }

    @Test func optionsAnyDash() {
        let text = "ls -la --color=auto - --"

        #expect(spans(text, .option) == [3..<6, 7..<15])
    }

    @Test func quotedAndVariableParts() {
        let text = "echo \"a $HOME\""

        #expect(spans(text, .string) == [5..<8, 13..<14])
        #expect(spans(text, .variable) == [8..<13])
    }

    @Test func quotedCommandIsCommandWhole() {
        let text = "'ls' x"

        #expect(spans(text, .command) == [0..<4])
        #expect(spans(text, .string).isEmpty)
        #expect(plan(text).commandsWithoutSpec == ["ls"])
    }

    @Test func redirectionIsOperatorAndTargetIsPathCandidate() {
        let result = plan("ls > out.txt")

        #expect(result.spans.filter { $0.role == .operator }.map(\.range) == [3..<4])
        #expect(result.pathCandidates == [PathCandidate(word: "out.txt", range: 5..<12)])
    }

    @Test func pathCandidatesSkipOptionsCommandsGlobsAndVariables() {
        let result = plan("cp -r src/ *.md ~/x $HOME/y 'a b'")

        #expect(result.pathCandidates.map(\.word) == ["src/", "~/x", "a b"])
    }

    @Test func escapedPathCandidateIsUnescaped() {
        #expect(plan("ls a\\ b").pathCandidates == [PathCandidate(word: "a b", range: 3..<7)])
    }

    @Test func subcommandIsNotPathCandidate() {
        #expect(plan("git checkout", specs: [Self.git]).pathCandidates.isEmpty)
    }

    @Test func pathCandidatesCappedAt16() {
        let words = (1...20).map { "f\($0)" }.joined(separator: " ")

        let result = plan("ls " + words)

        #expect(result.pathCandidates.count == 16)
        #expect(result.pathCandidates.first?.word == "f1")
        #expect(result.pathCandidates.last?.word == "f16")
    }

    @Test func missingSpecIsReported() {
        #expect(plan("git status | wc").commandsWithoutSpec == ["git", "wc"])
        #expect(plan("git status", specs: [Self.git]).commandsWithoutSpec.isEmpty)
    }

    @Test func unterminatedStringIsColoredToEnd() {
        #expect(spans("echo \"abc", .string) == [5..<9])
    }

    @Test func emptyLineHasNoSpans() {
        let result = plan("")

        #expect(result.spans.isEmpty)
        #expect(result.pathCandidates.isEmpty)
        #expect(result.commandsWithoutSpec.isEmpty)
    }

    @Test func spansAreSortedByStart() {
        let starts = plan("a \"x\" | b -c $d").spans.map(\.range.lowerBound)

        #expect(starts == starts.sorted())
    }

    // MARK: - Intermediate review 1

    @Test(arguments: [
        ("sudo -u root ls", [0..<4, 13..<15]), ("nice -n 10 make", [0..<4, 11..<15]),
        ("env -u VAR cmd", [0..<3, 11..<14]), ("exec -a name cmd", [0..<4, 13..<16]),
    ])
    func precommandOptionTakesItsArgument(_ text: String, _ commands: [Range<Int>]) {
        #expect(spans(text, .command) == commands)
    }

    @Test func arithmeticCommandIsNotACommand() {
        let text = "(( i++ )) && ls"

        #expect(spans(text, .command) == [13..<15])
        #expect(spans(text, .operator) == [0..<2, 7..<9, 10..<12])
    }

    @Test func arithmeticExpansionHasNoRole() {
        let result = plan("echo $((1+2)) x")

        #expect(result.spans == [HighlightSpan(range: 0..<4, role: .command)])
    }

    @Test func commandFromVariableHasNoCommandSpan() {
        let text = "$EDITOR notes.md"

        #expect(spans(text, .command).isEmpty)
        #expect(spans(text, .variable) == [0..<7])
        #expect(plan(text).pathCandidates.map(\.word) == ["notes.md"])
    }

    @Test func quotedVariableCommandHasNoCommandSpan() {
        let text = "\"$cmd\" x"

        #expect(spans(text, .command).isEmpty)
        #expect(spans(text, .variable) == [1..<5])
    }

    @Test func processSubstitutionStartsCommands() {
        #expect(spans("diff <(sort a) <(sort b)", .command) == [0..<4, 7..<11, 17..<21])
    }

    @Test func reservedWordsKeepCommandPosition() {
        let text = "if git status; then git push; fi"

        #expect(spans(text, .command) == [0..<2, 3..<6, 15..<19, 20..<23, 30..<32])
    }

    @Test func negationAndBraceKeepCommandPosition() {
        #expect(spans("! { ls; }", .command) == [0..<1, 2..<3, 4..<6, 8..<9])
    }

    @Test func forLoopVariableIsNotCommand() {
        let text = "for f in *; do echo $f; done"

        #expect(spans(text, .command) == [0..<3, 12..<14, 15..<19, 24..<28])
    }

    @Test func quotedValueOfLongOptionIsString() {
        let text = "git --msg=\"x\""

        #expect(spans(text, .option) == [4..<10])
        #expect(spans(text, .string) == [10..<13])
    }
}
