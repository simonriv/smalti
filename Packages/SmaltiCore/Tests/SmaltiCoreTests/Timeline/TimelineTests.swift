import Foundation
import SmaltiCore
import Testing

@Suite("Timeline")
struct TimelineTests {
    private typealias F = TimelineFixtures

    private func tools(_ turn: TimelineTurn) -> [ToolItem] {
        turn.items.compactMap { if case .tool(let tool) = $0 { tool } else { nil } }
    }

    @Test func aTurnStartsAtEachPrompt() {
        let timeline = Timeline().appending(F.workB)

        #expect(timeline.turns.count == 3)
        #expect(timeline.turnCount == 3)
        #expect(timeline.toolCount == 3)
        #expect(timeline.turns.map(\.items.count) == [4, 3, 2])
        #expect(timeline.startedAt == F.start.addingTimeInterval(100))
    }

    @Test func callsArePairedWithTheirResults() throws {
        let turn = Timeline().appending(F.workB).turns[0]

        let tools = tools(turn)
        #expect(tools.map(\.status) == [.failed(exitCode: 127), .done])
        #expect(tools[0].result?.output.excerpt == "Exit code 127\n(eval):1: command not found: eza")
        #expect(tools[0].name == "Bash")
    }

    @Test func aCallWithoutResultIsWorking() {
        let timeline = Timeline().appending([F.prompt("p", at: 1), F.call("x", "Bash", ["command": "sleep 9"], at: 2)])

        #expect(tools(timeline.turns[0]).map(\.status) == [.working])
    }

    @Test func anErrorWithoutExitCodeFails() {
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.call("x", "Bash", [:], at: 2), F.result("x", "denied", at: 3, isError: true),
        ])

        #expect(tools(timeline.turns[0]).map(\.status) == [.failed(exitCode: nil)])
    }

    @Test func repliesBeforeAnyPromptGoToATurnWithoutPrompt() {
        let timeline = Timeline().appending([F.reply("hola", at: 1), F.prompt("p", at: 2)])

        #expect(timeline.turns.count == 2)
        #expect(timeline.turnCount == 1)
        #expect(timeline.turns[0].prompt == nil)
    }

    @Test func aResultWithoutCallStaysWhereItCame() {
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.result("ghost", "out", at: 2), F.reply("r", at: 3),
        ])

        let items = timeline.turns[0].items
        #expect(items.count == 3)
        guard case .tool(let orphan) = items[1] else { Issue.record("expected the orphan result"); return }
        #expect(orphan.call == nil)
        #expect(orphan.name == "")
        #expect(orphan.status == .done)
    }

    @Test func subagentEntriesNestUnderTheirCall() throws {
        let agent = EntryScope.subagent("a8")
        let timeline = Timeline().appending([
            F.prompt("p", at: 1),
            F.call("t", "Agent", ["description": "cuenta"], at: 2),
            F.prompt("sub prompt", at: 3, scope: agent),
            F.call("s1", "Bash", ["command": "ls"], at: 4, scope: agent),
            F.result("s1", "2", at: 5, scope: agent),
            F.entry(.subagentLink(agentID: "a8", toolID: "t")),
            F.result("t", "done", at: 6),
        ])

        let agentTool = try #require(tools(timeline.turns[0]).first)
        #expect(timeline.turns.count == 1)
        #expect(agentTool.children.count == 2)
        #expect(timeline.toolCount == 2)
        guard case .tool(let child) = agentTool.children[1] else {
            Issue.record("expected the subagent's tool"); return
        }
        #expect(child.status == .done)
    }

    /// Review 1 (M14): "agentId: …" in some other tool's output links nothing.
    @Test func onlyAgentCallsTakeSubagents() {
        let timeline = Timeline().appending([
            F.prompt("p", at: 1), F.call("g", "Grep", ["pattern": "agentId"], at: 2),
            F.reply("sub", at: 3, scope: .subagent("a8")), F.entry(.subagentLink(agentID: "a8", toolID: "g")),
        ])

        guard case .tool(let grep) = timeline.item(.tool("g")) else { Issue.record("no grep"); return }
        #expect(grep.children.isEmpty)
        #expect(timeline.item(.agent("a8")) != nil)
    }

    @Test func aLinkArrivingAfterTheSubagentStillNests() throws {
        let agent = EntryScope.subagent("a8")
        let early = Timeline().appending([
            F.prompt("p", at: 1), F.call("t", "Agent", [:], at: 2), F.reply("sub", at: 3, scope: agent),
        ])

        let linked = early.appending([F.entry(.subagentLink(agentID: "a8", toolID: "t"))])

        #expect(early.turns.count == 2)
        #expect(try #require(tools(linked.turns[0]).first).children.count == 1)
        #expect(linked.turns.count == 1)
    }

    @Test func anUnlinkedSubagentGoesLastUnderItsOwnAgentItem() throws {
        let timeline = Timeline().appending([F.prompt("p", at: 1), F.reply("sub", at: 2, scope: .subagent("zz"))])

        let last = try #require(timeline.turns.last)
        #expect(timeline.turns.count == 2)
        let agent = try #require(tools(last).first)
        #expect(agent.id == TimelineItemID(rawValue: "agent:zz"))
        #expect(agent.children.count == 1)
    }

    @Test func compactionIsAnItemOfTheCurrentTurn() {
        let timeline = Timeline().appending([
            F.prompt("p", at: 1),
            F.entry(
                .compaction(
                    CompactionNote(preTokens: 1200, postTokens: 300, location: F.excerpt("", offset: 2).location))),
        ])

        guard case .compaction(let note) = timeline.turns[0].items[1] else {
            Issue.record("expected compaction"); return
        }
        #expect(note.preTokens == 1200)
    }

    @Test(arguments: 0...TimelineFixtures.workB.count)
    func appendingInTwoReadsEqualsOneRead(cut: Int) {
        let whole = Timeline().appending(F.workB)

        let split = Timeline().appending(Array(F.workB[..<cut])).appending(Array(F.workB[cut...]))

        #expect(split == whole)
    }

    @Test func noEntriesNoTurns() {
        let timeline = Timeline().appending([])

        #expect(timeline.turns.isEmpty)
        #expect(timeline.toolCount == 0)
        #expect(timeline.startedAt == nil)
    }

    @Test func itemsAreFoundByID() throws {
        let timeline = Timeline().appending(F.workB)
        let first = try #require(timeline.turns.first?.items.first)

        #expect(timeline.item(first.id) == first)
        #expect(timeline.item(TimelineItemID(rawValue: "tool:t3"))?.id == TimelineItemID(rawValue: "tool:t3"))
        #expect(timeline.item(TimelineItemID(rawValue: "nope")) == nil)
    }

    @Test func excerptsKeepTheLimitAndTheWholeSize() {
        let long = String(repeating: "é", count: 2_500) + "\nfin"

        let excerpt = F.excerpt(long, offset: 0)

        #expect(excerpt.excerpt.count == ExcerptText.limit)
        #expect(excerpt.isTruncated)
        #expect(excerpt.byteCount == long.utf8.count)
        #expect(excerpt.lineCount == 2)
        #expect(!F.excerpt("corto", offset: 0).isTruncated)
        #expect(F.excerpt("a\n\nb", offset: 0).lineCount == 3)
    }
}
