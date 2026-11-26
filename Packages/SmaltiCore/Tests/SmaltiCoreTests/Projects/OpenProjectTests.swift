import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Open project (F8.5)")
struct OpenProjectTests {
    private let files = InMemoryProjectFiles()
    private let records = InMemoryProjectRecords()
    private let root = "/Users/ana/dev/rizaria"
    private let workspace = WorkspaceID()

    private var useCase: OpenProject {
        OpenProject(
            files: files, records: records, harnesses: HarnessRegistry([FakeHarnessAdapter()]), home: "/Users/ana",
            clock: { projectDate })
    }

    private func prepared(_ step: ProjectStep) -> PreparedProject? {
        switch step {
        case .open(let prepared): prepared
        case .confirm(let confirmation): confirmation.prepared
        case .jump: nil
        }
    }

    @Test func firstTimeWithCommandsAsksAndRunsNothing() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"], nil]), at: root, fingerprint: "f1")

        let step = try useCase.prepare(root: root, open: [])

        guard case .confirm(let confirmation) = step else {
            Issue.record("expected a confirmation, got \(step)")
            return
        }
        #expect(confirmation.changes.isFirstTime)
        #expect(confirmation.changes.lines.map(\.command.command) == ["npm run dev"])
        #expect(confirmation.prepared.name.rawValue == "rizaria")
        #expect(confirmation.approvedAt == nil)
        #expect(records.writes == 0)
    }

    @Test func thePreparedWorkspaceIsTheProjects() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")

        let project = try #require(prepared(try useCase.prepare(root: root, open: [])))

        #expect(project.root == root)
        #expect(project.snapshot.project == root)
        #expect(project.snapshot.rootDirectory == root)
        #expect(project.snapshot.name == "rizaria")
        #expect(project.snapshot.panes[0].relaunch == RelaunchCommand(arguments: ["npm", "run", "dev"]))
        #expect(project.fingerprint == "f1")
    }

    @Test func approvingRemembersTheFingerprintAndOpening() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")
        let project = try #require(prepared(try useCase.prepare(root: root, open: [])))

        try useCase.opened(project)

        let record = try #require(records.all().first)
        #expect(record.root == root)
        #expect(record.lastOpened == projectDate)
        #expect(record.approval?.fingerprint == "f1")
        #expect(record.approval?.commands == [PlannedCommand(command: "npm run dev", place: nil)])
        #expect(record.approval?.paneCount == 1)
        #expect(record.approval?.layout == "dwindle")
    }

    @Test func anUnchangedFileOpensWithoutAsking() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")
        try useCase.opened(try #require(prepared(try useCase.prepare(root: root, open: []))))

        let step = try useCase.prepare(root: root, open: [])

        guard case .open = step else {
            Issue.record("expected to open, got \(step)")
            return
        }
    }

    @Test func aChangedFileAsksAgainShowingTheChange() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")
        try useCase.opened(try #require(prepared(try useCase.prepare(root: root, open: []))))
        files.put(projectLayout(commands: [["npm", "run", "dev"], ["make"]]), at: root, fingerprint: "f2")

        let step = try useCase.prepare(root: root, open: [])

        guard case .confirm(let confirmation) = step else {
            Issue.record("expected a confirmation, got \(step)")
            return
        }
        #expect(!confirmation.changes.isFirstTime)
        #expect(confirmation.changes.lines.map(\.kind) == [.same, .added])
        #expect(confirmation.approvedAt == projectDate)
    }

    @Test func onlyShellsOpensWithoutAsking() throws {
        files.put(projectLayout(commands: [nil, nil]), at: root, fingerprint: "f1")

        let step = try useCase.prepare(root: root, open: [])

        guard case .open = step else {
            Issue.record("expected to open, got \(step)")
            return
        }
    }

    @Test func anOpenProjectJumpsWithoutReadingTheFile() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")
        let open = [
            OpenProjectWorkspace(id: WorkspaceID(), project: nil, isInThisWindow: true, number: 1),
            OpenProjectWorkspace(id: workspace, project: root, isInThisWindow: false, number: 1),
        ]

        let step = try useCase.prepare(root: root, open: open)

        #expect(step == .jump(workspace))
        #expect(files.reads.isEmpty)
    }

    @Test func aLinkedRootIsTheSameProject() throws {
        files.link("/Users/ana/link", to: root)

        let step = try useCase.prepare(
            root: "/Users/ana/link",
            open: [OpenProjectWorkspace(id: workspace, project: root, isInThisWindow: true, number: 2)])

        #expect(step == .jump(workspace))
    }

    @Test func jumpingMovesTheProjectFirst() throws {
        try records.replace(with: [
            ProjectRecord(root: "/x", name: "x", lastOpened: projectDate, approval: nil),
            ProjectRecord(root: root, name: "rizaria", lastOpened: Date(timeIntervalSince1970: 0), approval: nil),
        ])

        try useCase.jumped(to: root)

        #expect(records.all().map(\.root) == [root, "/x"])
    }

    @Test func aMissingFileIsATypedError() {
        #expect(throws: ProjectFileError.missing(root: root)) { try useCase.prepare(root: root, open: []) }
    }

    @Test func anInvalidFileIsATypedError() {
        files.put(projectLayout(name: "", commands: [nil]), at: root, fingerprint: "f1")

        #expect(throws: ProjectFileError.invalid(.invalidName("", reason: "empty"))) {
            try useCase.prepare(root: root, open: [])
        }
    }

    @Test func commandsSayWhereTheyRunOutsideTheRoot() throws {
        var layout = projectLayout(commands: [["make"]])
        layout.panes = [SharedPane(directory: "api", command: ["make"])]
        files.put(layout, at: root, fingerprint: "f1")

        let project = try #require(prepared(try useCase.prepare(root: root, open: [])))

        #expect(project.commands == [PlannedCommand(command: "make", place: "api")])
    }

    @Test func aRecordsFailureIsTyped() throws {
        files.put(projectLayout(commands: [["ls"]]), at: root, fingerprint: "f1")
        let project = try #require(prepared(try useCase.prepare(root: root, open: [])))
        records.failWrites(with: .unwritable(path: "projects.json", reason: "disco lleno"))

        #expect(throws: ProjectFileError.unwritable(path: "projects.json", reason: "disco lleno")) {
            try useCase.opened(project)
        }
    }
}

@MainActor
@Suite("Open project, review 1 (F8.5)")
struct OpenProjectReviewTests {
    private let files = InMemoryProjectFiles()
    private let records = InMemoryProjectRecords()
    private let root = "/Users/ana/dev/rizaria"

    private var useCase: OpenProject {
        OpenProject(
            files: files, records: records, harnesses: HarnessRegistry([FakeHarnessAdapter()]), home: "/Users/ana",
            clock: { projectDate })
    }

    private func prepared(_ step: ProjectStep) -> PreparedProject? {
        switch step {
        case .open(let prepared): prepared
        case .confirm(let confirmation): confirmation.prepared
        case .jump: nil
        }
    }

    @Test func aLinkedPaneFolderThatLeavesTheRepoIsRefused() {
        var layout = projectLayout(commands: [["make"]])
        layout.panes = [SharedPane(directory: "tools", command: ["make"])]
        files.put(layout, at: root, fingerprint: "f1")
        files.link(root + "/tools", to: "/Users/ana/.ssh")

        #expect(throws: ProjectFileError.invalid(.outsideProject(pane: 1, path: "tools"))) {
            try useCase.prepare(root: root, open: [])
        }
    }

    @Test func aLinkedEditorFileThatLeavesTheRepoIsRefused() {
        var layout = projectLayout(commands: [nil])
        layout.panes = [SharedPane(directory: ".", editor: SharedEditor(file: "notes.md", line: 1))]
        files.put(layout, at: root, fingerprint: "f1")
        files.link(root + "/notes.md", to: "/etc/hosts")

        #expect(throws: ProjectFileError.invalid(.outsideProject(pane: 1, path: "notes.md"))) {
            try useCase.prepare(root: root, open: [])
        }
    }

    @Test func aLinkInsideTheRepoIsFine() throws {
        var layout = projectLayout(commands: [["make"]])
        layout.panes = [SharedPane(directory: "current", command: ["make"])]
        files.put(layout, at: root, fingerprint: "f1")
        files.link(root + "/current", to: root + "/releases/7")

        #expect(prepared(try useCase.prepare(root: root, open: [])) != nil)
    }

    @Test func whatOpensAndIsApprovedIsWhatWasShown() throws {
        files.put(projectLayout(commands: [["npm", "run", "dev"]]), at: root, fingerprint: "f1")
        let shown = try #require(prepared(try useCase.prepare(root: root, open: [])))
        files.put(projectLayout(commands: [["rm", "-rf", "build"]]), at: root, fingerprint: "f2")

        try useCase.opened(shown)

        let approval = try #require(records.all().first?.approval)
        #expect(approval.fingerprint == "f1")
        #expect(approval.commands == [PlannedCommand(command: "npm run dev", place: nil)])
        guard case .confirm = try useCase.prepare(root: root, open: []) else {
            Issue.record("the newer file still needs its own approval")
            return
        }
    }

    @Test func onlyRatiosChangedStillAsksSayingTheCommandsAreTheSame() throws {
        files.put(projectLayout(commands: [["ls"], nil]), at: root, fingerprint: "f1")
        try useCase.opened(try #require(prepared(try useCase.prepare(root: root, open: []))))
        files.put(projectLayout(commands: [["ls"], nil]), at: root, fingerprint: "f2")

        let step = try useCase.prepare(root: root, open: [])

        guard case .confirm(let confirmation) = step else {
            Issue.record("expected a confirmation, got \(step)")
            return
        }
        #expect(confirmation.changes.hasSameCommands)
    }

    @Test func aProjectWhoseFileWasDeletedStillJumpsToItsOpenWorkspace() throws {
        let workspace = WorkspaceID()
        try records.replace(with: [ProjectRecord(root: root, name: "rizaria", lastOpened: projectDate, approval: nil)])
        let list = ListProjects(files: files, records: records, home: "/Users/ana")
        let open = [OpenProjectWorkspace(id: workspace, project: root, isInThisWindow: true, number: 1)]

        #expect(try list.forgetMissing() == 1)
        #expect(list.execute(paneDirectories: [], focusedDirectory: nil, open: open).isEmpty)
        #expect(try useCase.prepare(root: root, open: open) == .jump(workspace))
    }
}
