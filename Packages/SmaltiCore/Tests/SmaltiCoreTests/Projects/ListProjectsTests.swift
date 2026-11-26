import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("List projects (F8.5)")
struct ListProjectsTests {
    private let files = InMemoryProjectFiles()
    private let records = InMemoryProjectRecords()
    private let home = "/Users/ana"

    private var useCase: ListProjects { ListProjects(files: files, records: records, home: home) }

    private func record(_ root: String, _ name: String, at seconds: TimeInterval) -> ProjectRecord {
        ProjectRecord(root: root, name: name, lastOpened: Date(timeIntervalSince1970: seconds), approval: nil)
    }

    @Test func recentsNewestFirst() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        files.put(projectLayout(name: "b", commands: [nil]), at: "/p/b", fingerprint: "2")
        try records.replace(with: [record("/p/a", "a", at: 1), record("/p/b", "b", at: 2)])

        let listed = useCase.execute(paneDirectories: [], focusedDirectory: nil, open: [])

        #expect(listed.map(\.name) == ["b", "a"])
        #expect(listed[0].lastOpened == Date(timeIntervalSince1970: 2))
        #expect(files.reads.isEmpty, "recents keep their remembered name")
    }

    @Test func dropsAndForgetsRecentsWhoseFileIsGone() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        try records.replace(with: [record("/p/a", "a", at: 1), record("/p/gone", "gone", at: 2)])
        let writesBefore = records.writes

        let removed = try useCase.forgetMissing()
        let listed = useCase.execute(paneDirectories: [], focusedDirectory: nil, open: [])

        #expect(removed == 1)
        #expect(listed.map(\.name) == ["a"])
        #expect(records.all().map(\.root) == ["/p/a"])
        #expect(records.writes == writesBefore + 1, "listing itself never writes")
    }

    @Test func forgettingNothingWritesNothing() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        try records.replace(with: [record("/p/a", "a", at: 1)])
        let writesBefore = records.writes

        #expect(try useCase.forgetMissing() == 0)
        #expect(records.writes == writesBefore)
    }

    @Test func aForgetFailureIsTyped() throws {
        try records.replace(with: [record("/p/gone", "gone", at: 2)])
        records.failWrites(with: .unwritable(path: "projects.json", reason: "x"))

        #expect(throws: ProjectFileError.unwritable(path: "projects.json", reason: "x")) {
            try useCase.forgetMissing()
        }
    }

    @Test func discoversFromPaneDirectoriesWithTheFilesName() {
        files.put(projectLayout(name: "Rizaria App", commands: [nil]), at: "/p/rizaria", fingerprint: "1")

        let listed = useCase.execute(
            paneDirectories: ["/p/rizaria/web", "/p/rizaria"], focusedDirectory: "/p/rizaria/web", open: [])

        #expect(listed.map(\.name) == ["Rizaria App"])
        #expect(listed[0].isInFocusedPane)
        #expect(listed[0].lastOpened == nil)
    }

    @Test func anUnreadableDiscoveredFileTakesTheFolderName() {
        files.fail(at: "/p/broken", with: .unreadable(root: "/p/broken", reason: "x"))

        let listed = useCase.execute(paneDirectories: ["/p/broken"], focusedDirectory: nil, open: [])

        #expect(listed.map(\.name) == ["broken"])
    }

    @Test func aDiscoveredRecentIsListedOnce() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        try records.replace(with: [record("/p/a", "a", at: 1)])

        let listed = useCase.execute(paneDirectories: ["/p/a/src"], focusedDirectory: "/p/a/src", open: [])

        #expect(listed.count == 1)
        #expect(listed[0].isInFocusedPane)
        #expect(listed[0].lastOpened != nil)
    }

    @Test func orderIsFocusedThenRecentsThenDiscoveredByName() throws {
        for name in ["focus", "old", "new", "zeta", "alfa"] {
            files.put(projectLayout(name: name, commands: [nil]), at: "/p/\(name)", fingerprint: name)
        }
        try records.replace(with: [record("/p/old", "old", at: 1), record("/p/new", "new", at: 2)])

        let listed = useCase.execute(
            paneDirectories: ["/p/zeta", "/p/alfa", "/p/focus"], focusedDirectory: "/p/focus", open: [])

        #expect(listed.map(\.name) == ["focus", "new", "old", "alfa", "zeta"])
    }

    @Test func marksWhereItIsOpen() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        try records.replace(with: [record("/p/a", "a", at: 1)])
        let workspace = OpenProjectWorkspace(id: WorkspaceID(), project: "/p/a", isInThisWindow: true, number: 2)

        let listed = useCase.execute(paneDirectories: [], focusedDirectory: nil, open: [workspace])

        #expect(listed[0].openIn == workspace)
    }

    @Test func aLinkedPaneDirectoryResolvesToTheRealRoot() throws {
        files.put(projectLayout(name: "a", commands: [nil]), at: "/p/a", fingerprint: "1")
        files.link("/link/a", to: "/p/a")
        try records.replace(with: [record("/p/a", "a", at: 1)])

        let listed = useCase.execute(paneDirectories: ["/link/a"], focusedDirectory: "/link/a", open: [])

        #expect(listed.map(\.root) == ["/p/a"])
        #expect(listed[0].isInFocusedPane)
    }
}
