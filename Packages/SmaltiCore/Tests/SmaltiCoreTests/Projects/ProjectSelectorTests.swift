import Foundation
import SmaltiCore
import Testing

@Suite("Project selector (F8.5)")
struct ProjectSelectorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func listing(
        _ name: String, opened hoursAgo: Double? = nil, focused: Bool = false,
        openIn: OpenProjectWorkspace? = nil
    ) -> ProjectListing {
        ProjectListing(
            root: "/Users/ana/dev/\(name)", name: name,
            lastOpened: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) }, isInFocusedPane: focused, openIn: openIn)
    }

    private func selector(_ listings: [ProjectListing], active: String? = nil) -> ProjectSelector {
        ProjectSelector(
            listings: listings, activeProject: active,
            context: .init(home: "/Users/ana", now: now, texts: .spanish, time: .spanish))
    }

    @Test func rowsSayWhereAndWhen() {
        let open = OpenProjectWorkspace(
            id: WorkspaceID(), project: "/Users/ana/dev/acme", isInThisWindow: true, number: 1)
        let rows = selector([
            listing("acme", opened: 0, openIn: open), listing("rizaria", opened: 2), listing("site", focused: true),
            listing("loose"),
        ]).rows

        #expect(rows.map(\.name) == ["acme", "rizaria", "site", "loose"])
        #expect(rows.map(\.path) == ["~/dev/acme", "~/dev/rizaria", "~/dev/site", "~/dev/loose"])
        #expect(rows.map(\.detail) == ["abierto · workspace 1", "hace 2 h", "en este panel", ""])
        #expect(rows.map(\.isOpen) == [true, false, false, false])
    }

    @Test func theActiveProjectIsNotPreselected() {
        let selector = selector([listing("acme"), listing("rizaria")], active: "/Users/ana/dev/acme")

        #expect(selector.selected == 1)
        #expect(selector.selectedRoot == "/Users/ana/dev/rizaria")
    }

    @Test func otherwiseTheFirst() {
        #expect(selector([listing("acme"), listing("rizaria")]).selected == 0)
    }

    @Test func movingWrapsAround() {
        let start = selector([listing("a"), listing("b"), listing("c")])

        #expect(start.moving(by: 1).selected == 1)
        #expect(start.moving(by: -1).selected == 2)
        #expect(start.moving(by: 1).moving(by: 1).moving(by: 1).selected == 0)
    }

    @Test func filteringMatchesNameOrPathAndSelectsTheFirst() {
        let filtered = selector([listing("acme"), listing("rizaria"), listing("site")]).moving(by: 2).filtering("riz")

        #expect(filtered.rows.map(\.name) == ["rizaria"])
        #expect(filtered.selected == 0)
        #expect(selector([listing("acme")]).filtering("dev/ac").rows.count == 1)
    }

    @Test func emptyAndNoMatchSayWhy() {
        #expect(selector([]).rows.isEmpty)
        #expect(selector([]).selectedRoot == nil)
        #expect(selector([]).emptyText == ProjectTexts.spanish.empty)
        #expect(selector([listing("acme")]).filtering("zzz").emptyText == "Ningún proyecto coincide con «zzz»")
        #expect(selector([]).moving(by: 1).selected == 0)
    }

    @Test func selectingAnIndexOutOfRangeKeepsTheSelection() {
        let start = selector([listing("a"), listing("b")])

        #expect(start.selecting(1).selected == 1)
        #expect(start.selecting(7).selected == 0)
    }
}
