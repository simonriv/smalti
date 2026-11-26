import Foundation
import SmaltiCore
import Testing

@Suite("TimelineSelection")
struct TimelineSelectionTests {
    private typealias F = TimelineFixtures

    private func rows(_ timeline: Timeline, expanded: Set<TimelineItemID> = []) -> [TimelineRow] {
        TimelineRows.rows(
            timeline, harness: .claude, expanded: expanded, policy: VerbatimText(), texts: .spanish, time: { _ in "" })
    }

    private var agentTimeline: Timeline {
        Timeline().appending([
            F.prompt("p", at: 1), F.call("t", "Agent", [:], at: 2),
            F.call("s1", "Bash", ["command": "ls"], at: 4, scope: .subagent("a8")),
            F.entry(.subagentLink(agentID: "a8", toolID: "t")), F.reply("fin", at: 5),
        ])
    }

    @Test func startsAtTheLastRowFollowingTheTail() {
        let all = rows(Timeline().appending(F.workB))

        let selection = TimelineSelection().updated(for: all)

        #expect(selection.selected == all.last?.id)
        #expect(selection.followsTail)
    }

    @Test func movingStopsAtTheEdges() {
        let all = rows(Timeline().appending(F.workB))
        let last = TimelineSelection().updated(for: all)

        #expect(last.moved(.down, in: all).selected == all.last?.id)
        let up = last.moved(.up, in: all)
        #expect(up.selected == all[all.count - 2].id)
        #expect(!up.followsTail)
        let top = (0..<20).reduce(up) { selection, _ in selection.moved(.up, in: all) }
        #expect(top.selected == all.first?.id)
    }

    @Test func movingBackToTheLastRowFollowsAgain() {
        let all = rows(Timeline().appending(F.workB))

        let selection = TimelineSelection().updated(for: all).moved(.up, in: all).moved(.down, in: all)

        #expect(selection.followsTail)
    }

    @Test func rightExpandsAToolAndNothingElse() {
        let all = rows(Timeline().appending(F.workB))
        let onTool = TimelineSelection(selected: all[1].id)
        let onPrompt = TimelineSelection(selected: all[0].id)

        #expect(onTool.expanding(in: all, expanded: []) == [all[1].id])
        #expect(onPrompt.expanding(in: all, expanded: []).isEmpty)
    }

    @Test func leftCollapsesThenClimbsToTheParent() {
        let agentID = TimelineItemID(rawValue: "tool:t")
        let child = TimelineItemID(rawValue: "tool:s1")
        let open = rows(agentTimeline, expanded: [agentID])

        let onChild = TimelineSelection(selected: child)
        let (climbed, stillOpen) = onChild.collapsing(in: open, expanded: [agentID])
        let (_, closed) = TimelineSelection(selected: agentID).collapsing(in: open, expanded: [agentID])

        #expect(climbed.selected == agentID)
        #expect(stillOpen == [agentID])
        #expect(closed.isEmpty)
    }

    @Test func newRowsMoveATailFollowerButNotAReader() {
        let before = rows(Timeline().appending(Array(F.workB.prefix(6))))
        let after = rows(Timeline().appending(F.workB))
        let follower = TimelineSelection().updated(for: before)
        let reader = TimelineSelection(selected: before[1].id)

        #expect(follower.updated(for: after).selected == after.last?.id)
        #expect(reader.updated(for: after).selected == before[1].id)
    }

    @Test func aVanishedSelectionFallsToTheNearestEarlierRow() {
        let all = rows(Timeline().appending(F.workB))
        let gone = TimelineSelection(selected: all[4].id)
        let shorter = Array(all[..<4]) + Array(all[5...])

        #expect(gone.updated(for: shorter, previous: all).selected == all[3].id)
        #expect(TimelineSelection(selected: all[0].id).updated(for: []).selected == nil)
    }
}
