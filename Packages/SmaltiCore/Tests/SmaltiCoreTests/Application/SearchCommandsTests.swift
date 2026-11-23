import SmaltiCore
import Testing

@MainActor
@Suite("SearchCommands")
struct SearchCommandsTests {
    private let search = SearchCommands(layouts: .standard)
    private let set: WorkspaceSet

    init() throws {
        let root = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
    }

    @Test func searchUsesCurrentState() {
        let results = search.execute("workspace", set: set, keymap: .standard)

        let ids = results.map(\.command.id)
        #expect(ids.contains(.workspaceNew))
        #expect(!ids.contains(.paneClose))
    }

    @Test func searchReflectsStateOfTheSet() {
        let withoutPanes = search.execute("cerrar panel", set: set, keymap: .standard)

        #expect(!withoutPanes.contains { $0.command.id == .paneClose })
    }

    @Test func emptyQueryReturnsEveryCommandInCatalogOrder() {
        let results = search.execute("", set: set, keymap: .standard)

        let catalog = CommandCatalog.commands(for: set, keymap: .standard, layouts: .standard)
        #expect(results.map(\.command) == catalog)
    }
}
