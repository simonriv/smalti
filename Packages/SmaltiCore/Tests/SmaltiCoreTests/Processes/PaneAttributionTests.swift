import SmaltiCore
import Testing

@Suite("PaneAttribution")
struct PaneAttributionTests {
    private typealias F = ProcessFixtures
    private let pane = PaneID()
    private let other = PaneID()

    /// Smalti (100) → login (101, root, tty 7) → zsh (102) → npm (103) → node (104); a `setsid` daemon (105) with no
    /// terminal under node; a detached server (106) re-parented to launchd; another pane: login (201, tty 8) → claude.
    private var records: [ProcessRecord] {
        [
            F.record(100, parent: 1, name: "Smalti"),
            F.record(101, parent: 100, name: "login", isOwn: false, terminal: 7),
            F.record(102, parent: 101, name: "zsh", terminal: 7),
            F.record(103, parent: 102, name: "npm", terminal: 7),
            F.record(104, parent: 103, name: "node", terminal: 7),
            F.record(105, parent: 104, name: "esbuild"),
            F.record(106, parent: 1, name: "detached"),
            F.record(201, parent: 100, name: "login", isOwn: false, terminal: 8),
            F.record(202, parent: 201, name: "claude", terminal: 8),
        ]
    }

    @Test func sameTerminalBelongsToThePane() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 104])

        #expect(attribution.pane(of: 102) == pane)
        #expect(attribution.pane(of: 104) == pane)
    }

    @Test func rootOwnedLeaderStillGivesTheTerminal() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [other: 201])

        #expect(attribution.pane(of: 202) == other)
    }

    @Test func processWithoutTerminalBelongsThroughItsAncestors() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 102])

        #expect(attribution.pane(of: 105) == pane)
    }

    @Test func detachedProcessHasNoPane() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 102, other: 201])

        #expect(attribution.pane(of: 106) == nil)
        #expect(attribution.pane(of: 100) == nil)
    }

    @Test func paneRootIsTheShell() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 104, other: 201])

        #expect(attribution.isPaneRoot(102))
        #expect(!attribution.isPaneRoot(103))
        #expect(attribution.isPaneRoot(202))
    }

    /// Review 1 (important 1): a double-forked server re-parented to launchd keeps the pane's terminal; it belongs to
    /// the pane but is not its shell.
    @Test func adoptedByLaunchdKeepsThePaneButIsNoShell() {
        let adopted = F.record(400, parent: 1, name: "python3", terminal: 7)
        let launchd = F.record(1, parent: 0, name: "launchd", isOwn: false)
        let attribution = PaneAttribution(records: records + [adopted, launchd], foregroundGroups: [pane: 102])

        #expect(attribution.pane(of: 400) == pane)
        #expect(!attribution.isPaneRoot(400))
    }

    /// Review 1 (minor 6): `sudo -u me cmd` in a pane: root's sudo on the pane's terminal is not the pane's top.
    @Test func childOfAnotherRootProcessInThePaneIsNoShell() {
        let sudo = F.record(500, parent: 102, name: "sudo", isOwn: false, terminal: 7)
        let command = F.record(501, parent: 500, name: "cmd", terminal: 7)
        let attribution = PaneAttribution(records: records + [sudo, command], foregroundGroups: [pane: 102])

        #expect(!attribution.isPaneRoot(501))
    }

    /// Mutation 1: a pane process whose parent record is missing (it ended between reads) counts as the top: the safe
    /// side is to protect it.
    @Test func unknownParentCountsAsThePaneTop() {
        let orphan = F.record(600, parent: 599, name: "zsh", terminal: 7)
        let attribution = PaneAttribution(records: records + [orphan], foregroundGroups: [pane: 102])

        #expect(attribution.isPaneRoot(600))
    }

    @Test func loginItselfIsNotAPaneProcess() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 104])

        #expect(attribution.pane(of: 101) == pane)
        #expect(!attribution.isPaneRoot(101))
    }

    @Test func unknownForegroundGroupAttributesNothing() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 999])

        #expect(attribution.pane(of: 104) == nil)
    }

    /// Final review (important 1): `cat file | less`: `cat`, the group's leader, ended, but the group stays in front.
    /// Its other members still name the pane's terminal, so the shell stays the pane's and stays protected.
    @Test func groupWhoseLeaderEndedStillGivesTheTerminal() {
        let less = F.record(110, parent: 102, name: "less", terminal: 7, processGroup: 109)
        let attribution = PaneAttribution(records: records + [less], foregroundGroups: [pane: 109])

        #expect(attribution.pane(of: 110) == pane)
        #expect(attribution.isPaneRoot(102))
    }

    @Test func parentCycleEnds() {
        let looped = [F.record(300, parent: 301, name: "a"), F.record(301, parent: 300, name: "b")]

        let attribution = PaneAttribution(records: looped, foregroundGroups: [pane: 999])

        #expect(attribution.pane(of: 300) == nil)
    }

    @Test func noPanesAttributesNothing() {
        #expect(PaneAttribution(records: records, foregroundGroups: [:]).pane(of: 104) == nil)
    }
}
