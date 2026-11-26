import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Projects, final review (F8.5)")
struct ProjectFinalReviewTests {
    private let root = "/Users/ana/dev/rizaria"

    private func opener(_ files: InMemoryProjectFiles, records: InMemoryProjectRecords = InMemoryProjectRecords())
        -> OpenProject
    {
        OpenProject(
            files: files, records: records, harnesses: HarnessRegistry([FakeHarnessAdapter()]), home: "/Users/ana",
            clock: { projectDate })
    }

    // MARK: A command never runs elsewhere than shown

    @Test func aMissingFolderOfACommandIsATypedError() {
        let files = InMemoryProjectFiles()
        var layout = projectLayout(commands: [["git", "clean", "-fdx"]])
        layout.panes = [SharedPane(directory: "build", command: ["git", "clean", "-fdx"])]
        files.put(layout, at: root, fingerprint: "f1")
        files.folders = [root]

        #expect(throws: ProjectFileError.missingFolder(pane: 1, path: "build")) {
            try opener(files).prepare(root: root, open: [])
        }
    }

    @Test(arguments: [
        SharedPane(directory: "gone", harness: .claude),
        SharedPane(directory: "gone", editor: SharedEditor(file: "a.md", line: 1)),
    ])
    func aMissingFolderOfAnAgentOrAnEditorIsATypedError(pane: SharedPane) {
        let files = InMemoryProjectFiles()
        var layout = projectLayout(commands: [nil])
        layout.panes = [pane]
        files.put(layout, at: root, fingerprint: "f1")
        files.folders = [root]

        #expect(throws: ProjectFileError.missingFolder(pane: 1, path: "gone")) {
            try opener(files).prepare(root: root, open: [])
        }
    }

    @Test func aMissingFolderOfAShellIsFine() throws {
        let files = InMemoryProjectFiles()
        var layout = projectLayout(commands: [nil])
        layout.panes = [SharedPane(directory: "build")]
        files.put(layout, at: root, fingerprint: "f1")
        files.folders = [root]

        _ = try opener(files).prepare(root: root, open: [])
    }

    @Test func aProjectPaneThatFallsBackRunsNothing() throws {
        let engine = FakeTerminalEngine()
        engine.failingDirectories = ["/tmp/gone"]
        let restore = RestoreSession(
            .init(
                engine: engine, transcripts: InMemorySessionArchive(), harnesses: HarnessRegistry([]),
                environment: PaneEnvironment(version: "2", files: PaneFileLocator(stateDirectory: URL(filePath: "/s"))),
                shell: .custom("/bin/zsh -f"), clock: { projectDate }, texts: .spanish))
        let pane = PlannedPane(
            id: UUID(), workingDirectory: "/tmp/gone", restoresScrollback: false, restoresHistory: false,
            launch: .relaunch(RelaunchCommand(arguments: ["git", "clean", "-fdx"])))
        let project = PlannedWorkspace(
            name: "p", rootDirectory: "/tmp", layout: .dwindle, tree: nil, focusedIndex: 0, panes: [pane],
            project: "/tmp")
        let plain = PlannedWorkspace(
            name: "p", rootDirectory: "/tmp", layout: .dwindle, tree: nil, focusedIndex: 0, panes: [pane])

        let result = restore.execute(
            RestorePlan(workspaces: [project], activeIndex: 0), savedAt: projectDate,
            home: try WorkingDirectory(path: "/tmp"))

        #expect(engine.openedSpecs.last?.initialInput == nil, "a project's command never runs in a fallback folder")
        #expect(result.failures.contains { $0.contains("git clean -fdx") && $0.contains("/tmp/gone") })
        _ = restore.execute(
            RestorePlan(workspaces: [plain], activeIndex: 0), savedAt: projectDate,
            home: try WorkingDirectory(path: "/tmp"))
        #expect(engine.openedSpecs.last?.initialInput != nil, "other workspaces keep F2's behaviour")
    }

    // MARK: What is approved is what is shown

    @Test func anUnknownHarnessAsksAndSaysSo() throws {
        let files = InMemoryProjectFiles()
        var layout = projectLayout(commands: [nil])
        layout.panes = [SharedPane(directory: ".", harness: HarnessID(rawValue: "foo"))]
        files.put(layout, at: root, fingerprint: "f1")

        guard case .confirm(let confirmation) = try opener(files).prepare(root: root, open: []) else {
            Issue.record("a file Smalti degrades asks first")
            return
        }
        #expect(confirmation.warnings == [.unknownHarness(pane: 1, name: "foo")])
    }

    @Test func theSameFileWithOtherComputedCommandsAsksAgain() throws {
        let files = InMemoryProjectFiles()
        let records = InMemoryProjectRecords()
        files.put(projectLayout(commands: [["make"]]), at: root, fingerprint: "f1")
        let approval = ProjectApproval(
            fingerprint: "f1", approvedAt: projectDate, commands: [PlannedCommand(command: "other", place: nil)],
            paneCount: 1, layout: "dwindle")
        try records.replace(with: [
            ProjectRecord(root: root, name: "rizaria", lastOpened: projectDate, approval: approval)
        ])

        guard case .confirm = try opener(files, records: records).prepare(root: root, open: []) else {
            Issue.record("the approval covers the commands shown, not only the bytes")
            return
        }
    }

    @Test func theCardSaysTheWarnings() throws {
        let files = InMemoryProjectFiles()
        var layout = projectLayout(commands: [["make"]], layout: "spiral")
        layout.panes = [SharedPane(directory: ".", command: ["make"])]
        files.put(layout, at: root, fingerprint: "f1")
        guard case .confirm(let confirmation) = try opener(files).prepare(root: root, open: []) else {
            Issue.record("expected a confirmation")
            return
        }

        let card = ProjectCard.opening(
            confirmation,
            context: .init(
                home: "/Users/ana", now: projectDate, texts: .spanish, session: .spanish,
                layoutNames: CommandTexts.spanish.layoutNames))

        #expect(card.extra?.contains("spiral") == true)
    }

    // MARK: Paths

    @Test func theFilterMatchesThePathAsShown() {
        let selector = ProjectSelector(
            listings: [
                ProjectListing(
                    root: "/Users/ana/dev/rizaria", name: "r", lastOpened: nil, isInFocusedPane: false, openIn: nil)
            ], activeProject: nil,
            context: .init(home: "/Users/ana", now: projectDate, texts: .spanish, time: .spanish))

        #expect(selector.filtering("~/dev").rows.count == 1)
        #expect(selector.filtering("/Users/ana").rows.isEmpty)
    }

    @Test func savingResolvesArgumentsThroughLinks() throws {
        let files = InMemoryProjectFiles()
        files.link("/tmp/r", to: "/private/tmp/r")
        files.link("/tmp/r/scripts/x.sh", to: "/private/tmp/r/scripts/x.sh")
        let saver = SaveProjectLayout(
            files: files, records: InMemoryProjectRecords(), harnesses: HarnessRegistry([]), home: "/Users/ana",
            clock: { projectDate })
        var workspace = Workspace.empty(
            name: "r", rootDirectory: try WorkingDirectory(path: "/tmp/r"), layout: DwindleLayout())
        let running = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp/r")).applying(
            .foregroundProcessChanged(ForegroundProcess(name: "x.sh", commandLine: ["/tmp/r/scripts/x.sh"])))
        workspace = workspace.adding(running)

        let step = try saver.prepare(workspace.markingProject("/private/tmp/r"), focusedDirectory: "/tmp/r")

        guard case .write(let pending) = step else {
            Issue.record("expected a write")
            return
        }
        #expect(pending.layout.panes[0].command == ["./scripts/x.sh"])
    }
}
