import Foundation
import SmaltiCore
import Testing

@Suite("Recent projects (F8.5)")
struct RecentProjectsTests {
    private func record(_ name: String, at seconds: TimeInterval, approval: ProjectApproval? = nil) -> ProjectRecord {
        ProjectRecord(
            root: "/r/\(name)", name: name, lastOpened: Date(timeIntervalSince1970: seconds), approval: approval)
    }

    private let approval = ProjectApproval(
        fingerprint: "f1", approvedAt: Date(timeIntervalSince1970: 5), commands: [], paneCount: 1, layout: "dwindle")

    @Test func newestFirst() {
        let recents = RecentProjects(records: [record("a", at: 1), record("c", at: 3), record("b", at: 2)])

        #expect(recents.ordered.map(\.name) == ["c", "b", "a"])
    }

    @Test func reopeningMovesUpWithoutDuplicatingAndKeepsTheApproval() {
        let recents = RecentProjects(records: [record("a", at: 1, approval: approval), record("b", at: 2)])

        let updated = recents.opening(root: "/r/a", name: "a2", at: Date(timeIntervalSince1970: 9), approval: nil)

        #expect(updated.ordered.map(\.root) == ["/r/a", "/r/b"])
        #expect(updated.ordered[0].name == "a2")
        #expect(updated.ordered[0].approval == approval)
    }

    @Test func aNewApprovalReplacesTheOld() {
        let newer = ProjectApproval(
            fingerprint: "f2", approvedAt: Date(timeIntervalSince1970: 9), commands: [], paneCount: 2, layout: "columns"
        )

        let updated = RecentProjects(records: [record("a", at: 1, approval: approval)])
            .opening(root: "/r/a", name: "a", at: Date(timeIntervalSince1970: 9), approval: newer)

        #expect(updated.ordered[0].approval == newer)
    }

    @Test func keepsAtMostTwentyDroppingTheOldest() {
        let full = RecentProjects(records: (1...20).map { record("p\($0)", at: TimeInterval($0)) })

        let updated = full.opening(root: "/r/new", name: "new", at: Date(timeIntervalSince1970: 100), approval: nil)

        #expect(RecentProjects.maximumCount == 20)
        #expect(updated.ordered.count == 20)
        #expect(updated.ordered.first?.name == "new")
        #expect(!updated.ordered.contains { $0.name == "p1" })
        #expect(updated.ordered.contains { $0.name == "p2" })
    }

    @Test func pruningDropsTheMissingAndCountsThem() {
        let recents = RecentProjects(records: [record("a", at: 1), record("b", at: 2), record("c", at: 3)])

        let (kept, removed) = recents.pruned { $0 != "/r/b" }

        #expect(kept.ordered.map(\.name) == ["c", "a"])
        #expect(removed == 1)
    }

    @Test func pruningNothingRemovesNothing() {
        let (kept, removed) = RecentProjects(records: [record("a", at: 1)]).pruned { _ in true }

        #expect(kept.ordered.count == 1)
        #expect(removed == 0)
    }

    @Test func recordFindsByRoot() {
        let recents = RecentProjects(records: [record("a", at: 1)])

        #expect(recents.record(at: "/r/a")?.name == "a")
        #expect(recents.record(at: "/r/z") == nil)
    }
}
