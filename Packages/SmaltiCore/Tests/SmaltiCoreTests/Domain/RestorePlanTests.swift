import Foundation
import SmaltiCore
import Testing

@Suite("RestorePlan")
struct RestorePlanTests {
    private let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let resume = AgentSnapshot(harness: .claude, sessionID: "7f3a", title: "Recordatorios", lastState: .waiting)
    private let finished = AgentSnapshot(harness: .claude, sessionID: "c41e", title: "Pagos", lastState: .stopped)
    private let server = RelaunchCommand(arguments: ["pnpm", "dev"])

    private func pane(agent: AgentSnapshot? = nil, relaunch: RelaunchCommand? = nil) -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(), workingDirectory: "/Users/s/dev/solen", title: nil, processName: nil, scrollbackLines: 1240,
            commandCount: 38, relaunch: relaunch, agent: agent)
    }

    private func workspace(_ name: String, _ panes: [PaneSnapshot], focusedIndex: Int? = 0) -> WorkspaceSnapshot {
        let tree: SnapshotTree? =
            panes.count == 2
            ? .split(axis: .sideBySide, ratio: 0.7, first: .leaf(index: 0), second: .leaf(index: 1)) : nil
        return WorkspaceSnapshot(
            name: name, rootDirectory: "/Users/s/dev/\(name)", layout: "dwindle", tree: tree,
            focusedIndex: panes.isEmpty ? nil : focusedIndex, panes: panes)
    }

    private func snapshot(_ workspaces: [WorkspaceSnapshot], activeIndex: Int = 0) -> SessionSnapshot {
        SessionSnapshot(
            version: SessionSnapshot.formatVersion, savedAt: savedAt, workspaces: workspaces, activeIndex: activeIndex)
    }

    private func onlyPane(_ plan: RestorePlan) -> PlannedPane? { plan.workspaces.first?.panes.first }

    @Test func fullRestoresShellScrollbackAndHistory() {
        let saved = snapshot([workspace("solen", [pane()])])

        let planned = onlyPane(RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved)))

        #expect(planned?.restoresScrollback == true)
        #expect(planned?.restoresHistory == true)
        #expect(planned?.launch == .shell)
        #expect(planned?.workingDirectory == "/Users/s/dev/solen")
    }

    @Test func agentPaneResumesWithoutScrollback() {
        let saved = snapshot([workspace("solen", [pane(agent: resume)])])

        let planned = onlyPane(RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved)))

        #expect(planned?.launch == .resume(resume))
        #expect(planned?.restoresScrollback == false)
        #expect(planned?.restoresHistory == true)
    }

    @Test func relaunchPaneRunsCommandWithoutScrollback() {
        let relaunching = pane(relaunch: server)
        let saved = snapshot([workspace("solen", [relaunching])])
        let selection = RestoreSelection.defaults(for: saved).toggling(relaunching.id)

        let planned = onlyPane(RestorePlan.make(from: saved, mode: .full, selection: selection))

        #expect(planned?.launch == .relaunch(server))
        #expect(planned?.restoresScrollback == false)
    }

    @Test func layoutsOnlyOpensCleanShells() {
        let saved = snapshot([workspace("solen", [pane(), pane(agent: resume)])])

        let plan = RestorePlan.make(from: saved, mode: .layoutsOnly, selection: .defaults(for: saved))

        let panes = plan.workspaces[0].panes
        #expect(panes.map(\.launch) == [.shell, .shell])
        #expect(panes.allSatisfy { !$0.restoresScrollback && !$0.restoresHistory })
        #expect(plan.workspaces[0].tree != nil)
    }

    @Test func uncheckedPaneIsSkipped() {
        let kept = pane()
        let dropped = pane()
        let saved = snapshot([workspace("solen", [kept, dropped])])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: RestoreSelection(unchecked: [dropped.id]))

        #expect(plan.workspaces[0].panes.map(\.id) == [kept.id])
    }

    @Test func workspaceWithoutCheckedPanesIsSkipped() {
        let lonely = pane()
        let saved = snapshot([workspace("solen", [lonely]), workspace("rizaria", [pane()])])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: RestoreSelection(unchecked: [lonely.id]))

        #expect(plan.workspaces.map(\.name) == ["rizaria"])
    }

    @Test func emptyWorkspaceIsSkipped() {
        let saved = snapshot([workspace("vacío", []), workspace("rizaria", [pane()])])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved))

        #expect(plan.workspaces.map(\.name) == ["rizaria"])
    }

    @Test func removedPaneDropsManualTreeAndRefocuses() {
        let first = pane()
        let focused = pane()
        let saved = snapshot([workspace("solen", [first, focused], focusedIndex: 1)])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: RestoreSelection(unchecked: [focused.id]))

        #expect(plan.workspaces[0].tree == nil)
        #expect(plan.workspaces[0].focusedIndex == 0)
    }

    @Test func keptPanesKeepTreeAndFocus() {
        let saved = snapshot([workspace("solen", [pane(), pane()], focusedIndex: 1)])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved))

        #expect(plan.workspaces[0].tree == saved.workspaces[0].tree)
        #expect(plan.workspaces[0].focusedIndex == 1)
        #expect(plan.workspaces[0].layout == .dwindle)
    }

    @Test func activeIndexFollowsSkippedWorkspaces() {
        let lonely = pane()
        let saved = snapshot(
            [workspace("solen", [lonely]), workspace("rizaria", [pane()]), workspace("xolken", [pane()])],
            activeIndex: 2)

        let plan = RestorePlan.make(from: saved, mode: .full, selection: RestoreSelection(unchecked: [lonely.id]))

        #expect(plan.activeIndex == 1)
    }

    @Test func activeWorkspaceSkippedFallsBackToFirst() {
        let lonely = pane()
        let saved = snapshot([workspace("solen", [pane()]), workspace("rizaria", [lonely])], activeIndex: 1)

        let plan = RestorePlan.make(from: saved, mode: .full, selection: RestoreSelection(unchecked: [lonely.id]))

        #expect(plan.activeIndex == 0)
    }

    @Test func defaultsUncheckRelaunchAndStoppedAgents() {
        let relaunching = pane(relaunch: server)
        let stopped = pane(agent: finished)
        let saved = snapshot([workspace("solen", [pane(), pane(agent: resume), relaunching, stopped])])

        #expect(RestoreSelection.defaults(for: saved).unchecked == [relaunching.id, stopped.id])
    }

    @Test func checkedCountCountsSelectedPanes() {
        let relaunching = pane(relaunch: server)
        let saved = snapshot([workspace("solen", [pane(), relaunching]), workspace("rizaria", [pane()])])

        #expect(RestoreSelection.defaults(for: saved).checkedCount(in: saved) == 2)
    }

    @Test func togglingTwiceRestoresSelection() {
        let id = UUID()

        #expect(RestoreSelection(unchecked: []).toggling(id).toggling(id) == RestoreSelection(unchecked: []))
    }

    @Test func emptySnapshotPlansNothing() {
        let saved = snapshot([])

        let plan = RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved))

        #expect(plan.workspaces.isEmpty)
        #expect(plan.activeIndex == 0)
    }

    @Test func layoutIDIsCarriedAsSavedForTheCatalogToResolve() {
        let saved = SessionSnapshot(
            version: 1, savedAt: savedAt,
            workspaces: [
                WorkspaceSnapshot(
                    name: "s", rootDirectory: "/tmp", layout: "spiral", tree: nil, focusedIndex: 0, panes: [pane()])
            ], activeIndex: 0)

        let plan = RestorePlan.make(from: saved, mode: .full, selection: .defaults(for: saved))

        #expect(plan.workspaces[0].layout == LayoutID(rawValue: "spiral"))
    }
}
