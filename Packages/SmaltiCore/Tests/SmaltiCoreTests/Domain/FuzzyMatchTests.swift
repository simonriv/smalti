import SmaltiCore
import Testing

@Suite("fuzzyMatch")
struct FuzzyMatchTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/Users/s")
    }

    private func command(_ title: String, subtitle: String? = nil, id: String? = nil) -> Command {
        Command(
            id: CommandID(rawValue: id ?? title), title: title, subtitle: subtitle, group: .panes, shortcut: nil,
            isCurrent: false)
    }

    private func catalog() -> [Command] {
        CommandCatalog.commands(
            for: WorkspaceSet(
                first: Workspace.empty(
                    name: "w", rootDirectory: root,
                    layout: DwindleLayout())),
            keymap: .standard, layouts: .standard)
    }

    @Test func layQueryRanksThreeLayoutsFirst() {
        let ranked = fuzzyMatch("lay", in: catalog())

        #expect(ranked.prefix(3).map(\.command.id) == [.layoutDwindle, .layoutColumns, .layoutMaster])
    }

    @Test func queryIgnoresCaseAndAccents() {
        let ranked = fuzzyMatch("TAMANOS", in: [command("Igualar tamaños de paneles"), command("Nuevo panel")])

        #expect(ranked.map(\.command.title) == ["Igualar tamaños de paneles"])
    }

    @Test func accentedQueryMatchesPlainText() {
        let ranked = fuzzyMatch("configuración", in: [command("Recargar configuracion")])

        #expect(ranked.count == 1)
    }

    @Test func emptyQueryKeepsCatalogOrder() {
        let commands = [command("b"), command("a"), command("c")]

        let ranked = fuzzyMatch("", in: commands)

        #expect(ranked.map(\.command) == commands)
        #expect(ranked.allSatisfy { $0.score == 0 })
    }

    @Test func nonMatchingQueryReturnsNothing() {
        #expect(fuzzyMatch("zzz", in: catalog()).isEmpty)
    }

    @Test func queryMustBeASubsequenceInOrder() {
        #expect(fuzzyMatch("ba", in: [command("ab")]).isEmpty)
    }

    @Test func subtitleIsSearchable() {
        let ranked = fuzzyMatch(
            "divide", in: [command("Layout: Dwindle", subtitle: "cada panel nuevo divide el último")])

        #expect(ranked.count == 1)
    }

    @Test func titlePrefixScoresExactly() {
        // "ab": consecutive +10, word start of "a" +8, title prefix +15, nothing skipped.
        let ranked = fuzzyMatch("ab", in: [command("abc")])

        #expect(ranked.first?.score == 33)
    }

    @Test func skippedCharactersCostOnePointEach() {
        // "ac" in "abc": "a" starts the word +8, "c" after one skipped character -1, and "abc" does not start with "ac".
        let ranked = fuzzyMatch("ac", in: [command("abc")])

        #expect(ranked.first?.score == 7)
    }

    @Test func wordStartBeatsMidWordMatch() {
        let ranked = fuzzyMatch("p", in: [command("Cerrar panel"), command("Nuevo workspace")])

        #expect(ranked.first?.command.title == "Cerrar panel")
    }

    @Test func tiesKeepCatalogOrder() {
        let commands = [command("xa"), command("xb"), command("xc")]

        let ranked = fuzzyMatch("x", in: commands)

        #expect(ranked.map(\.command) == commands)
    }

    @Test func higherScoreComesFirst() {
        let ranked = fuzzyMatch("pan", in: [command("Cerrar panel"), command("Panel nuevo")])

        #expect(ranked.map(\.command.title) == ["Panel nuevo", "Cerrar panel"])
    }
}
