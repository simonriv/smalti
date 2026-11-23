import Foundation
import SmaltiCore
import Testing

enum SpecFixtures {
    static let git = CompletionSpec(
        name: ["git"], description: "Control de versiones",
        subcommands: [
            CompletionSpec(name: ["checkout"], description: "Cambiar de rama o restaurar"),
            CompletionSpec(name: ["cherry-pick"], description: "Aplicar commits existentes"),
            CompletionSpec(name: ["check-ignore"], description: "Depurar .gitignore"),
            CompletionSpec(
                name: ["commit"], description: "Guardar cambios",
                options: [
                    OptionSpec(names: ["-m", "--message"], args: [ArgSpec(name: "message")]),
                    OptionSpec(names: ["-a", "--all"]),
                ]),
            CompletionSpec(name: ["status"], description: "Estado del árbol"),
        ],
        options: [OptionSpec(names: ["-C"], args: [ArgSpec(name: "path", templates: [.folders])])])

    static let cd = CompletionSpec(name: ["cd"], args: [ArgSpec(name: "directory", templates: [.folders])])
}

@Suite("CompletionEngine")
struct CompletionEngineTests {
    private func line(_ text: String) -> InputLine { InputLine(text: text, cursor: text.unicodeScalars.count) }

    @Test func targetIsSubcommandAfterCommand() {
        #expect(
            CompletionEngine.target(for: line("git ch"), spec: SpecFixtures.git)
                == .subcommandOrOption(prefix: "ch", spec: SpecFixtures.git))
    }

    @Test func targetSkipsOptionsAndTheirValues() {
        #expect(
            CompletionEngine.target(for: line("git -C repo ch"), spec: SpecFixtures.git)
                == .subcommandOrOption(prefix: "ch", spec: SpecFixtures.git))
    }

    @Test func targetIsOptionValue() {
        let commit = SpecFixtures.git.subcommands[3]

        #expect(
            CompletionEngine.target(for: line("git commit -m "), spec: SpecFixtures.git)
                == .optionValue(commit.options[0], prefix: ""))
    }

    @Test func targetIsArgumentWithTemplate() {
        #expect(
            CompletionEngine.target(for: line("cd Pro"), spec: SpecFixtures.cd)
                == .argument(SpecFixtures.cd.args[0], prefix: "Pro"))
    }

    @Test func targetAfterSeparatorUsesLastCommand() {
        #expect(
            CompletionEngine.target(for: line("ls && git ch"), spec: SpecFixtures.git)
                == .subcommandOrOption(prefix: "ch", spec: SpecFixtures.git))
    }

    @Test func targetForAnotherCommandIsNil() {
        #expect(CompletionEngine.target(for: line("npm r"), spec: SpecFixtures.git) == nil)
    }

    @Test func dashPrefixListsOptions() {
        let commit = SpecFixtures.git.subcommands[3]

        let names = CompletionEngine.suggestions(for: .subcommandOrOption(prefix: "-", spec: commit)).map(\.name)

        #expect(names == ["-m", "--message", "-a", "--all"])
    }

    @Test func wordPrefixListsSubcommands() {
        let names = CompletionEngine.suggestions(for: .subcommandOrOption(prefix: "ch", spec: SpecFixtures.git)).map(
            \.name)

        #expect(names == ["checkout", "cherry-pick", "check-ignore", "commit", "status"])
    }

    @Test func rankPrefixBeforeFuzzy() {
        let items = ["status", "checkout", "cherry-pick", "commit"].map { Suggestion(name: $0) }

        let ranked = CompletionEngine.rank(items, prefix: "ch", history: nil).map(\.name)

        #expect(ranked == ["checkout", "cherry-pick"])
    }

    @Test func rankKeepsFuzzyMatchesAfterPrefixMatches() {
        let items = ["status", "cherry-pick", "stash"].map { Suggestion(name: $0) }

        #expect(CompletionEngine.rank(items, prefix: "sh", history: nil).map(\.name) == ["stash"])
        #expect(CompletionEngine.rank(items, prefix: "st", history: nil).map(\.name) == ["status", "stash"])
    }

    @Test func rankBreaksTiesByHistoryUse() {
        let items = ["checkout", "cherry-pick"].map { Suggestion(name: $0) }
        let history = HistoryIndex(
            entries: [historyEntry("git cherry-pick abc", at: 1), historyEntry("git cherry-pick def", at: 2)],
            limit: 10)

        #expect(
            CompletionEngine.rank(items, prefix: "ch", history: history).map(\.name) == ["cherry-pick", "checkout"])
    }

    @Test func insertionAddsSpace() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "checkout"), into: line("git ch"))

        #expect(inserted == InputLine(text: "git checkout ", cursor: 13))
    }

    @Test func insertionKeepsFolderSlash() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "Projects/"), into: line("cd Pro"))

        #expect(inserted == InputLine(text: "cd Projects/", cursor: 12))
    }

    @Test func insertionEscapesSpaces() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "My Folder/"), into: line("cd My"))

        #expect(inserted.text == "cd My\\ Folder/")
    }

    @Test func insertionUsesInsertValueAndItsCursor() {
        let suggestion = Suggestion(name: "commit -m 'msg'", insertValue: "commit -m '{cursor}'")

        let inserted = CompletionEngine.insertion(of: suggestion, into: line("git co"))

        #expect(inserted == InputLine(text: "git commit -m ''", cursor: 15))
    }

    @Test func insertionKeepsTextAfterTheCursor() {
        let inserted = CompletionEngine.insertion(
            of: Suggestion(name: "status"), into: InputLine(text: "git st && ls", cursor: 6))

        #expect(inserted == InputLine(text: "git status  && ls", cursor: 11))
    }
}
