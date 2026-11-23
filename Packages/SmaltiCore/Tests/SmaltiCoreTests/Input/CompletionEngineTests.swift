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

    // Review I1: completing inside a quoted word keeps the quote and closes it.
    @Test func insertionInsideDoubleQuotesClosesThem() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "My File.txt"), into: line("cat \"My Fi"))

        #expect(inserted.text == "cat \"My File.txt\" ")
    }

    @Test func insertionOfAFolderInsideQuotesLeavesThemOpen() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "My Folder/"), into: line("cd 'My F"))

        #expect(inserted == InputLine(text: "cd 'My Folder/", cursor: 14))
    }

    @Test func insertionEscapesDoubleQuoteMetacharacters() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "a$b\"c"), into: line("cat \"a"))

        #expect(inserted.text == "cat \"a\\$b\\\"c\" ")
    }

    @Test func insertionInsideSingleQuotesEscapesTheQuote() {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: "Tom's.txt"), into: line("cat 'To"))

        #expect(inserted.text == "cat 'Tom'\\''s.txt' ")
    }

    // Review I2: unquoted names escape every zsh metacharacter.
    @Test(arguments: [
        ("Doc (1).pdf", "Doc\\ \\(1\\).pdf "), ("Tom's notes.txt", "Tom\\'s\\ notes.txt "),
        ("a&b;c|d", "a\\&b\\;c\\|d "), ("$HOME*?", "\\$HOME\\*\\? "), ("~x=y", "\\~x=y "),
        ("=cmd", "\\=cmd "), ("#tag", "\\#tag "),
    ])
    func insertionEscapesZshMetacharacters(name: String, expected: String) {
        let inserted = CompletionEngine.insertion(of: Suggestion(name: name), into: line("open "))

        #expect(inserted.text == "open " + expected)
    }

    // Review I3: the rest of the word after the cursor is replaced, not duplicated.
    @Test func insertionReplacesTheWholeWordAroundTheCursor() {
        let inserted = CompletionEngine.insertion(
            of: Suggestion(name: "checkout"), into: InputLine(text: "git chekout main", cursor: 7))

        #expect(inserted == InputLine(text: "git checkout  main", cursor: 13))
    }

    @Test func targetUsesTheTextBeforeTheCursor() {
        #expect(
            CompletionEngine.target(for: InputLine(text: "git chekout", cursor: 6), spec: SpecFixtures.git)
                == .subcommandOrOption(prefix: "ch", spec: SpecFixtures.git))
    }

    @Test func prefixInsertionEscapesAndAddsNothing() {
        #expect(
            CompletionEngine.insertion(ofPrefix: "My F", into: line("cd My")) == InputLine(text: "cd My\\ F", cursor: 8)
        )
    }
}
