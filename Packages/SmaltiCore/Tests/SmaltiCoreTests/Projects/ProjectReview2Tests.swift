import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Projects, review 2 (F8.5)")
struct ProjectReview2Tests {
    private let root = "/Users/ana/dev/rizaria"

    @Test func aHeldKeyNeverConfirms() {
        #expect(ConfirmationKey.confirms(isRepeat: false))
        #expect(!ConfirmationKey.confirms(isRepeat: true))
    }

    @Test func approvingAProjectOpenedMeanwhileJumpsInstead() throws {
        let files = InMemoryProjectFiles()
        let opener = OpenProject(
            files: files, records: InMemoryProjectRecords(), harnesses: HarnessRegistry([]), home: "/Users/ana",
            clock: { projectDate })
        files.put(projectLayout(commands: [["make"]]), at: root, fingerprint: "f1")
        guard case .confirm(let confirmation) = try opener.prepare(root: root, open: []) else {
            Issue.record("expected a confirmation")
            return
        }
        let other = WorkspaceID()

        let late = opener.approved(
            confirmation.prepared,
            open: [OpenProjectWorkspace(id: other, project: root, isInThisWindow: false, number: 1)])

        #expect(late == .jump(other))
        #expect(opener.approved(confirmation.prepared, open: []) == .open(confirmation.prepared))
    }

    @Test func savingMarksTheWorkspaceOnlyWhenNoOtherIsTheProjects() {
        let active = WorkspaceID()
        let other = OpenProjectWorkspace(id: WorkspaceID(), project: root, isInThisWindow: true, number: 1)
        let itself = OpenProjectWorkspace(id: active, project: root, isInThisWindow: true, number: 2)

        #expect(SaveProjectLayout.marks(root, active: active, open: []))
        #expect(SaveProjectLayout.marks(root, active: active, open: [itself]))
        #expect(!SaveProjectLayout.marks(root, active: active, open: [other, itself]))
    }

    @Test func theSelectorSaysAnotherWindow() {
        let far = OpenProjectWorkspace(id: WorkspaceID(), project: root, isInThisWindow: false, number: 3)
        let selector = ProjectSelector(
            listings: [
                ProjectListing(root: root, name: "rizaria", lastOpened: nil, isInFocusedPane: false, openIn: far)
            ],
            activeProject: nil, context: .init(home: "/Users/ana", now: projectDate, texts: .spanish, time: .spanish))

        #expect(selector.rows.first?.detail == "abierto en otra ventana")
        #expect(selector.rows.first?.isOpen == true)
    }

    @Test func recentAndSaveRowsHaveTheirIcons() throws {
        var state = CatalogState(
            workspaces: WorkspaceSet(
                first: .empty(name: "t", rootDirectory: try WorkingDirectory(path: "/tmp"), layout: DwindleLayout())))
        state.projects = CatalogProjects(listings: [], home: "/Users/ana", saveRoot: root)

        let commands = CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: .spanish)

        #expect(commands.first { $0.id == .projectRecent }?.icon == .recentProjects)
        #expect(commands.first { $0.id == .projectSave }?.icon == .saveProject)
    }

    @Test func newTextsOfTheReview() {
        #expect(
            ProjectTexts.spanish.listFailed(["reason": "x"]) == "No se pudo actualizar la lista de proyectos: x")
        #expect(
            ProjectTexts.english.openedNotRemembered(["name": "a", "reason": "x"])
                == "Project “a” opened, but its approval couldn’t be remembered: x")
    }

    @Test func thePathMatchesAsWrittenNotLetterByLetter() {
        let listings = [
            ProjectListing(
                root: "/Users/ana/code/smalti-projects/rizaria", name: "rizaria", lastOpened: nil,
                isInFocusedPane: false,
                openIn: nil),
            ProjectListing(
                root: "/Users/ana/code/smalti-projects/acme", name: "acme", lastOpened: nil, isInFocusedPane: false,
                openIn: nil),
        ]
        let selector = ProjectSelector(
            listings: listings, activeProject: nil,
            context: .init(home: "/Users/ana", now: projectDate, texts: .spanish, time: .spanish))

        #expect(selector.filtering("acm").rows.map(\.name) == ["acme"])
        #expect(selector.filtering("code/smalti").rows.count == 2)
    }
}
