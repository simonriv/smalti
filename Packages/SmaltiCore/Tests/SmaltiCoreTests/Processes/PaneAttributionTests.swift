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

    @Test func loginItselfIsNotAPaneProcess() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 104])

        #expect(attribution.pane(of: 101) == pane)
        #expect(!attribution.isPaneRoot(101))
    }

    @Test func unknownForegroundGroupAttributesNothing() {
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 999])

        #expect(attribution.pane(of: 104) == nil)
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
