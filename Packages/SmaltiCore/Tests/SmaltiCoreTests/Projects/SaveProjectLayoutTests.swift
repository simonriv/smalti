import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Save project layout (F8.5)")
struct SaveProjectLayoutTests {
    private let files = InMemoryProjectFiles()
    private let records = InMemoryProjectRecords()
    private let home = "/Users/ana"

    private var useCase: SaveProjectLayout {
        SaveProjectLayout(
            files: files, records: records, harnesses: HarnessRegistry([]), home: home, clock: { projectDate })
    }

    private func workspace(_ directories: [String], project: String? = nil, relaunch: [String]? = nil) throws
        -> Workspace
    {
        let first = try WorkingDirectory(path: directories[0])
        var workspace = Workspace.empty(name: "w", rootDirectory: first, layout: DwindleLayout())
        for directory in directories {
            workspace = workspace.adding(Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: directory)))
        }
        return project.map { workspace.markingProject($0) } ?? workspace
    }

    private func pending(_ step: ProjectSaveStep) -> PendingProjectSave {
        switch step {
        case .write(let pending), .confirmReplace(let pending): pending
        }
    }

    @Test func theWorkspacesProjectIsTheRoot() throws {
        let step = try useCase.prepare(
            try workspace(["/p/app/web"], project: "/p/app"), focusedDirectory: "/p/app/web")

        #expect(pending(step).root == "/p/app")
    }

    @Test func otherwiseTheDiscoveredProject() throws {
        files.put(projectLayout(name: "Mi App", commands: [nil]), at: "/p/app", fingerprint: "1")

        let step = try useCase.prepare(try workspace(["/p/app/web"]), focusedDirectory: "/p/app/web")

        guard case .confirmReplace(let pending) = step else {
            Issue.record("an existing file asks before replacing, got \(step)")
            return
        }
        #expect(pending.root == "/p/app")
        #expect(pending.layout.name == "Mi App")
    }

    @Test func otherwiseTheNearestRepository() throws {
        let files = InMemoryProjectFiles(repositoryRoots: ["/p/repo"])
        let useCase = SaveProjectLayout(
            files: files, records: records, harnesses: HarnessRegistry([]), home: home, clock: { projectDate })

        let step = try useCase.prepare(try workspace(["/p/repo/a/b"]), focusedDirectory: "/p/repo/a/b")

        #expect(step == .write(pending(step)))
        #expect(pending(step).root == "/p/repo")
        #expect(pending(step).layout.name == "repo")
        #expect(pending(step).layout.panes.map(\.directory) == ["a/b"])
    }

    @Test func otherwiseThePanesFolder() throws {
        let step = try useCase.prepare(try workspace(["/p/loose"]), focusedDirectory: "/p/loose")

        #expect(pending(step).root == "/p/loose")
    }

    @Test func aFolderThatIsNotAValidNameIsCalledProject() throws {
        let step = try useCase.prepare(try workspace(["/p/.hidden"]), focusedDirectory: "/p/.hidden")

        #expect(pending(step).layout.name == "project")
    }

    @Test func aPaneOutsideTheRootRefusesWithoutWriting() throws {
        #expect(throws: ProjectSaveError.layout(.outsideProject(pane: 2, path: "~/notes"))) {
            try useCase.prepare(
                try workspace(["/p/app", "/Users/ana/notes"], project: "/p/app"), focusedDirectory: "/p/app")
        }
        #expect(files.writes.isEmpty)
    }

    @Test func writingApprovesWhatItWrote() throws {
        let step = try useCase.prepare(
            try workspace(["/p/app"], project: "/p/app"), focusedDirectory: "/p/app")

        let name = try useCase.write(pending(step))

        #expect(name.rawValue == "app")
        #expect(files.writes.map(\.root) == ["/p/app"])
        let record = try #require(records.all().first)
        #expect(record.root == "/p/app")
        #expect(record.approval?.fingerprint == "written-1")
        #expect(record.lastOpened == projectDate)
    }

    @Test func aWriteFailureIsTyped() throws {
        files.failWrites(with: .unwritable(path: "/p/app/.smalti/layout.json", reason: "solo lectura"))
        let step = try useCase.prepare(try workspace(["/p/app"], project: "/p/app"), focusedDirectory: "/p/app")

        #expect(throws: ProjectSaveError.file(.unwritable(path: "/p/app/.smalti/layout.json", reason: "solo lectura")))
        {
            try useCase.write(pending(step))
        }
        #expect(records.all().isEmpty)
    }
}

@Suite("Layout name for projects (F8.5)")
struct ProjectLayoutNameTests {
    @Test func theFallbackIsAValidName() throws {
        #expect(try LayoutName(LayoutName.project.rawValue) == .project)
        #expect(LayoutName.project.rawValue == "project")
    }
}

@MainActor
@Suite("Save project layout, review 1 (F8.5)")
struct SaveProjectLayoutReviewTests {
    private let files = InMemoryProjectFiles()
    private let records = InMemoryProjectRecords()

    private var useCase: SaveProjectLayout {
        SaveProjectLayout(
            files: files, records: records, harnesses: HarnessRegistry([FakeHarnessAdapter()]), home: "/Users/ana",
            clock: { projectDate })
    }

    private func pending(_ step: ProjectSaveStep) -> PendingProjectSave {
        switch step {
        case .write(let pending), .confirmReplace(let pending): pending
        }
    }

    @Test func aPaneReachedThroughALinkIsInsideTheRepo() throws {
        files.link("/tmp/r", to: "/private/tmp/r")
        files.link("/tmp/r/api", to: "/private/tmp/r/api")
        var workspace = Workspace.empty(
            name: "r", rootDirectory: try WorkingDirectory(path: "/tmp/r"), layout: DwindleLayout())
        workspace = workspace.adding(Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp/r")))
        workspace = workspace.adding(Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp/r/api")))

        let step = try useCase.prepare(workspace.markingProject("/private/tmp/r"), focusedDirectory: "/tmp/r")

        #expect(pending(step).layout.panes.map(\.directory) == [".", "api"])
    }
}

@Suite("Project discovery, nearest repository (F8.5)")
struct NearestRepositoryTests {
    @Test func climbsToTheNearestGitFolderButNeverTheHome() {
        let files = InMemoryProjectFiles(repositoryRoots: ["/p/repo", "/Users/ana"])
        let discovery = ProjectDiscovery(files: files, home: "/Users/ana")

        #expect(discovery.nearestRepository(from: "/p/repo/a/b") == "/p/repo")
        #expect(discovery.nearestRepository(from: "/Users/ana/notes") == nil)
        #expect(discovery.nearestRepository(from: "/q/x") == nil)
    }
}
