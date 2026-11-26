import SmaltiCore
import Testing

@MainActor
@Suite("SearchCommands")
struct SearchCommandsTests {
    private let search = SearchCommands(layouts: .standard, texts: .spanish)
    private let set: WorkspaceSet

    init() throws {
        let root = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
    }

    @Test func searchUsesCurrentState() {
        let results = search.execute("workspace", state: CatalogState(workspaces: set), keymap: .standard)

        let ids = results.map(\.command.id)
        #expect(ids.contains(.workspaceNew))
        #expect(!ids.contains(.paneClose))
    }

    @Test func searchReflectsStateOfTheSet() {
        let withoutPanes = search.execute("cerrar panel", state: CatalogState(workspaces: set), keymap: .standard)

        #expect(!withoutPanes.contains { $0.command.id == .paneClose })
    }

    @Test func emptyQueryReturnsEveryCommandInCatalogOrder() {
        let results = search.execute("", state: CatalogState(workspaces: set), keymap: .standard)

        let catalog = CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard, layouts: .standard, texts: .spanish)
        #expect(results.map(\.command) == catalog)
    }
}
