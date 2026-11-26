import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Project workspace (F8.5)")
struct ProjectWorkspaceTests {
    @Test func aWorkspaceRemembersItsProject() throws {
        let workspace = Workspace.empty(
            name: "w", rootDirectory: try WorkingDirectory(path: "/p/app"), layout: DwindleLayout())

        #expect(workspace.project == nil)
        #expect(workspace.markingProject("/p/app").project == "/p/app")
        #expect(workspace.markingProject("/p/app") != workspace)
    }

    @Test func theSnapshotCarriesTheProject() throws {
        let snapshot = WorkspaceSnapshot(
            name: "app", rootDirectory: "/p/app", layout: "dwindle", tree: nil, focusedIndex: nil, panes: [],
            project: "/p/app")

        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: try JSONEncoder().encode(snapshot))

        #expect(decoded.project == "/p/app")
    }

    @Test func anOlderSnapshotWithoutTheKeyDecodes() throws {
        let json = #"{"name":"a","rootDirectory":"/a","layout":"dwindle","panes":[]}"#

        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))

        #expect(decoded.project == nil)
    }

    @Test func aSessionWorkspaceRestoresAsTheProject() throws {
        let engine = FakeTerminalEngine()
        let restore = RestoreSession(
            .init(
                engine: engine, transcripts: InMemorySessionArchive(), harnesses: HarnessRegistry([]),
                environment: PaneEnvironment(version: "2", files: PaneFileLocator(stateDirectory: URL(filePath: "/s"))),
                shell: .custom("/bin/zsh -f"), clock: { projectDate }, texts: .spanish))
        let planned = PlannedWorkspace(
            name: "app", rootDirectory: "/tmp", layout: .dwindle, tree: nil, focusedIndex: 0,
            panes: [
                PlannedPane(
                    id: UUID(), workingDirectory: "/tmp", restoresScrollback: false, restoresHistory: false,
                    launch: .shell)
            ], project: "/p/app")

        let restored = restore.execute(
            RestorePlan(workspaces: [planned], activeIndex: 0), savedAt: projectDate,
            home: try WorkingDirectory(path: "/tmp"))

        #expect(restored.set?.active.project == "/p/app")
    }

    @Test func theRestorePlanKeepsTheProject() {
        let window = WindowSnapshot(
            frame: nil, isFullScreen: false,
            workspaces: [
                WorkspaceSnapshot(
                    name: "app", rootDirectory: "/p/app", layout: "dwindle", tree: .leaf(index: 0), focusedIndex: 0,
                    panes: [
                        PaneSnapshot(
                            id: UUID(), workingDirectory: "/p/app", title: nil, processName: nil, scrollbackLines: 0,
                            commandCount: 0, relaunch: nil, agent: nil)
                    ], project: "/p/app")
            ], activeIndex: 0)

        let plan = RestorePlan.make(from: window, mode: .full, selection: RestoreSelection(unchecked: []))

        #expect(plan.workspaces.first?.project == "/p/app")
    }
}

@MainActor
@Suite("Project workspace opening (F8.5)")
struct ProjectWorkspaceOpeningTests {
    private let layouts = InMemoryNamedLayouts()

    private var restore: RestoreNamedLayout {
        RestoreNamedLayout(
            layouts: layouts,
            restore: RestoreSession(
                .init(
                    engine: FakeTerminalEngine(), transcripts: InMemorySessionArchive(), harnesses: HarnessRegistry([]),
                    environment: PaneEnvironment(
                        version: "2", files: PaneFileLocator(stateDirectory: URL(filePath: "/s"))),
                    shell: .custom("/bin/zsh -f"), clock: { projectDate }, texts: .spanish)))
    }

    private func snapshot(project: String?) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            name: "app", rootDirectory: "/tmp", layout: "dwindle", tree: .leaf(index: 0), focusedIndex: 0,
            panes: [
                PaneSnapshot(
                    id: UUID(), workingDirectory: "/tmp", title: nil, processName: nil, scrollbackLines: 0,
                    commandCount: 0, relaunch: nil, agent: nil)
            ], project: project)
    }

    private func set() throws -> WorkspaceSet {
        WorkspaceSet(
            first: Workspace.empty(
                name: "w", rootDirectory: try WorkingDirectory(path: "/tmp"), layout: DwindleLayout()))
    }

    @Test func openingAProjectMarksItsWorkspace() throws {
        var workspaces = try set()

        _ = restore.open(
            project: snapshot(project: "/p/app"), into: &workspaces, home: try WorkingDirectory(path: "/tmp"))

        #expect(workspaces.workspaces.count == 2)
        #expect(workspaces.active.project == "/p/app")
        #expect(workspaces.active.name == "app")
    }

    @Test func aSavedLayoutNeverOpensAsAProject() throws {
        var workspaces = try set()
        let name = try LayoutName("app")
        try layouts.save(snapshot(project: "/p/app"), as: name)

        _ = try restore.execute(name, into: &workspaces, home: try WorkingDirectory(path: "/tmp"))

        #expect(workspaces.active.project == nil)
    }
}
