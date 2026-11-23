import SmaltiCore
import Testing

@Suite("Command sections")
struct CommandSectionTests {
    private func ranked(_ id: String, _ group: CommandGroup, score: Int) -> RankedCommand {
        RankedCommand(
            command: Command(
                id: CommandID(rawValue: id), title: id, subtitle: nil, group: group, shortcut: nil, isCurrent: false),
            score: score)
    }

    /// Groups appear in the order of their best result; rows keep their rank inside each group, and the flattened
    /// order is the order on screen (so ↑↓ follow what the user sees).
    @Test func interleavedGroupsAreGatheredByFirstAppearance() {
        let results = [
            ranked("t1", .tiling, score: 30), ranked("w2", .workspaces, score: 20), ranked("t3", .tiling, score: 10),
        ]

        let sections = CommandSection.grouping(results)

        #expect(sections.map(\.group) == [.tiling, .workspaces])
        #expect(sections.flatMap(\.commands).map(\.command.id.rawValue) == ["t1", "t3", "w2"])
    }

    @Test func noResultsGiveNoSections() {
        #expect(CommandSection.grouping([]).isEmpty)
    }
}
