import SmaltiCore
import Testing

@Suite("WorkspaceSet")
struct WorkspaceSetTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/Users/s")
    }

    private func makeWorkspace(_ name: String = "w") -> Workspace {
        Workspace.empty(name: name, rootDirectory: root, layout: DwindleLayout())
    }

    private func makePane() -> Pane {
        Pane(id: PaneID(), workingDirectory: root)
    }

    private func makeSet(_ count: Int) -> WorkspaceSet {
        (1..<count).reduce(WorkspaceSet(first: makeWorkspace("w0"))) { set, index in
            set.adding(makeWorkspace("w\(index)"))
        }
    }

    @Test func addingActivatesNewWorkspace() {
        let added = makeWorkspace("new")

        let set = WorkspaceSet(first: makeWorkspace()).adding(added)

        #expect(set.workspaces.count == 2)
        #expect(set.activeID == added.id)
        #expect(set.active == added)
    }

    @Test func activatingByIndexIsOneBased() {
        let set = makeSet(3)

        let result = set.activating(index: 1)

        #expect(result.activeID == set.workspaces[0].id)
    }

    @Test(arguments: [0, 4, -1])
    func activatingOutOfRangeDoesNothing(index: Int) {
        let set = makeSet(3)

        #expect(set.activating(index: index) == set)
    }

    @Test func activatingUnknownIDDoesNothing() {
        let set = makeSet(2)

        #expect(set.activating(WorkspaceID()) == set)
    }

    @Test func activatingByIDChangesActive() {
        let set = makeSet(3)

        #expect(set.activating(set.workspaces[1].id).activeID == set.workspaces[1].id)
    }

    @Test func closingActiveActivatesPrevious() throws {
        let set = makeSet(3).activating(index: 2)

        let result = try set.removing(set.activeID)

        #expect(result.workspaces.count == 2)
        #expect(result.activeID == set.workspaces[0].id)
    }

    @Test func closingFirstActiveActivatesNext() throws {
        let set = makeSet(3).activating(index: 1)

        let result = try set.removing(set.activeID)

        #expect(result.activeID == set.workspaces[1].id)
    }

    @Test func closingInactiveKeepsActive() throws {
        let set = makeSet(3)

        let result = try set.removing(set.workspaces[0].id)

        #expect(result.activeID == set.activeID)
    }

    @Test func closingOnlyWorkspaceThrows() {
        let set = WorkspaceSet(first: makeWorkspace())

        #expect(throws: WorkspaceSetError.cannotCloseLastWorkspace) {
            try set.removing(set.activeID)
        }
    }

    @Test func updatingTransformsOnlyTheTarget() {
        let set = makeSet(2)
        let target = set.workspaces[0].id

        let result = set.updating(target) { $0.renamed("renamed") }

        #expect(result.workspaces.map(\.name) == ["renamed", "w1"])
    }

    @Test func findsWorkspaceContainingPane() {
        let pane = makePane()
        let set = makeSet(2)
        let owner = set.workspaces[0].id

        let result = set.updating(owner) { $0.adding(pane) }

        #expect(result.workspace(containing: pane.id) == owner)
        #expect(result.workspace(containing: PaneID()) == nil)
    }

    @Test func paneIndexOnlyCountsActiveWorkspace() {
        let pane = makePane()
        let set = makeSet(2)
        let inactive = set.workspaces[0].id
        let withPane = set.updating(inactive) { $0.adding(pane) }

        #expect(withPane.paneIndex(of: pane.id) == nil)
        #expect(withPane.activating(inactive).paneIndex(of: pane.id) == 1)
    }

    @Test func paneIndexAboveNineIsNil() {
        let panes = (0..<10).map { _ in makePane() }
        let set = WorkspaceSet(first: panes.reduce(makeWorkspace()) { $0.adding($1) })

        #expect(set.paneIndex(of: panes[8].id) == 9)
        #expect(set.paneIndex(of: panes[9].id) == nil)
    }
}
