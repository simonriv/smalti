import Foundation
import SmaltiCore
import Testing

@Suite("Project layout (F8.5)")
struct ProjectLayoutTests {
    private let home = "/Users/ana"
    private let root = "/Users/ana/dev/rizaria"
    // Safe: "rizaria" has none of what `LayoutName` rejects.
    private let name = try! LayoutName("rizaria")

    private func pane(_ directory: String, relaunch: [String]? = nil, editor: EditorPosition? = nil) -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(), workingDirectory: directory, title: nil, processName: nil, scrollbackLines: 0,
            commandCount: 0, relaunch: relaunch.map(RelaunchCommand.init(arguments:)), agent: nil, editor: editor)
    }

    private func snapshot(_ panes: [PaneSnapshot]) -> WorkspaceSnapshot {
        let tree = panes.indices.dropFirst().reduce(SnapshotTree.leaf(index: 0)) {
            .split(axis: .sideBySide, ratio: 0.4, first: $0, second: .leaf(index: $1))
        }
        return WorkspaceSnapshot(
            name: "x", rootDirectory: root, layout: "columns", tree: tree, focusedIndex: 1, panes: panes)
    }

    private func project(root: String = ".", panes: [SharedPane]) -> SharedLayout {
        SharedLayout(
            smaltiLayout: 1, name: "rizaria", root: root, layout: "dwindle", focused: 0,
            tree: panes.count == 1 ? .leaf(index: 0) : nil, panes: panes)
    }

    // MARK: Validation

    @Test func projectRootIsTheDot() throws {
        let validated = try project(panes: [SharedPane(directory: ".")]).validatedAsProject()

        #expect(validated.name == name)
        #expect(SharedLayout.projectRoot == ".")
    }

    @Test func projectRejectsAnyOtherRoot() {
        #expect(throws: SharedLayoutError.invalidRoot("~/dev/rizaria")) {
            try project(root: "~/dev/rizaria", panes: [SharedPane(directory: ".")]).validatedAsProject()
        }
    }

    @Test func importStillRejectsTheDot() {
        #expect(throws: SharedLayoutError.invalidRoot(".")) {
            try project(panes: [SharedPane(directory: ".")]).validated()
        }
    }

    @Test func projectRejectsDirectoriesOutsideTheRepo() {
        let panes = [SharedPane(directory: "."), SharedPane(directory: "~/.ssh")]
        #expect(throws: SharedLayoutError.outsideProject(pane: 2, path: "~/.ssh")) {
            try project(panes: panes).validatedAsProject()
        }
        #expect(throws: SharedLayoutError.outsideProject(pane: 1, path: "/etc")) {
            try project(panes: [SharedPane(directory: "/etc")]).validatedAsProject()
        }
    }

    @Test func projectRejectsAnEditorFileOutsideTheRepo() {
        let pane = SharedPane(directory: ".", editor: SharedEditor(file: "/etc/hosts", line: 1))
        #expect(throws: SharedLayoutError.outsideProject(pane: 1, path: "/etc/hosts")) {
            try project(panes: [pane]).validatedAsProject()
        }
    }

    @Test func projectKeepsTheSharedChecks() {
        #expect(throws: SharedLayoutError.escapingDirectory(pane: 1, path: "../x")) {
            try project(panes: [SharedPane(directory: "../x")]).validatedAsProject()
        }
        #expect(throws: SharedLayoutError.emptyCommand(pane: 1)) {
            try project(panes: [SharedPane(directory: ".", command: [""])]).validatedAsProject()
        }
    }

    @Test func outsideProjectHasItsMessage() {
        let error = SharedLayoutError.outsideProject(pane: 2, path: "~/.ssh")

        #expect(error.message(.spanish) == "el panel 2 está fuera del proyecto: ~/.ssh")
        #expect(error.message(.english) == "pane 2 is outside the project: ~/.ssh")
    }

    // MARK: Export

    @Test func exportWritesEverythingRelativeToTheRepo() throws {
        let source = snapshot([
            pane(root, relaunch: ["npm", "run", "dev"]),
            pane(root + "/api", editor: EditorPosition(file: root + "/api/main.ts", line: 3)),
        ])

        let layout = try SharedLayout(exportingProject: source, named: name, root: root, home: home)

        #expect(layout.root == ".")
        #expect(layout.panes.map(\.directory) == [".", "api"])
        #expect(layout.panes[1].editor == SharedEditor(file: "main.ts", line: 3))
    }

    @Test func exportRefusesAPaneOutsideTheRepo() {
        let source = snapshot([pane(root), pane(home + "/notes")])

        #expect(throws: SharedLayoutError.outsideProject(pane: 2, path: "~/notes")) {
            try SharedLayout(exportingProject: source, named: name, root: root, home: home)
        }
    }

    @Test func exportRefusesAnEditorFileOutsideTheRepo() {
        let source = snapshot([pane(root, editor: EditorPosition(file: "/tmp/x.txt", line: 1))])

        #expect(throws: SharedLayoutError.outsideProject(pane: 1, path: "/tmp/x.txt")) {
            try SharedLayout(exportingProject: source, named: name, root: root, home: home)
        }
    }

    @Test func exportedProjectRoundTrips() throws {
        let source = snapshot([
            pane(root, relaunch: ["npm", "run", "dev"]), pane(root + "/web"),
            pane(root, editor: EditorPosition(file: root + "/README.md", line: 9)),
        ])
        let clone = "/Volumes/work/rizaria"

        let layout = try SharedLayout(exportingProject: source, named: name, root: root, home: home)
        let reopened = try layout.validatedAsProject().layout.workspaceSnapshot(root: clone, home: home)

        #expect(reopened.rootDirectory == clone)
        #expect(reopened.tree == source.tree)
        #expect(reopened.layout == "columns")
        #expect(reopened.focusedIndex == 1)
        #expect(reopened.panes.map(\.workingDirectory) == [clone, clone + "/web", clone])
        #expect(reopened.panes[0].relaunch == RelaunchCommand(arguments: ["npm", "run", "dev"]))
        #expect(reopened.panes[2].editor == EditorPosition(file: clone + "/README.md", line: 9))
    }
}
