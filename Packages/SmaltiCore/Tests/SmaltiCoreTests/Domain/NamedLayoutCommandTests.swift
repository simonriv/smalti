import SmaltiCore
import Testing

@MainActor
@Suite("Named layout commands")
struct NamedLayoutCommandTests {
    private let set: WorkspaceSet

    init() throws {
        set = WorkspaceSet(
            first: .empty(name: "solen", rootDirectory: try WorkingDirectory(path: "/tmp"), layout: DwindleLayout()))
    }

    private func summary(_ name: String, panes: Int, agents: Int) throws -> NamedLayoutSummary {
        NamedLayoutSummary(name: try LayoutName(name), paneCount: panes, agentCount: agents)
    }

    private func id(_ id: CommandID) -> (Command) -> Bool { { $0.id == id } }

    private func search(_ query: String, saved: [NamedLayoutSummary] = []) -> [Command] {
        SearchCommands(layouts: .standard, texts: .spanish).execute(
            query, state: CatalogState(workspaces: set, savedLayouts: saved), keymap: .standard
        )
        .map(\.command)
    }

    @Test func catalogListsSavedLayoutsWithSubtitle() throws {
        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: set, savedLayouts: [try summary("rizaria-full", panes: 4, agents: 2)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        let restore = commands.first(where: id(.layoutRestore(try LayoutName("rizaria-full"))))
        #expect(restore?.title == "Restaurar layout “rizaria-full”")
        #expect(restore?.subtitle == "— 4 paneles, retoma 2 sesiones de Claude")
        #expect(restore?.group == .workspaces)
    }

    @Test func catalogOmitsAgentClauseWithoutAgents() throws {
        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: set, savedLayouts: [try summary("solo", panes: 1, agents: 0)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        #expect(commands.first(where: id(.layoutRestore(try LayoutName("solo"))))?.subtitle == "— 1 panel")
    }

    @Test func oneAgentIsSingular() throws {
        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: set, savedLayouts: [try summary("uno", panes: 2, agents: 1)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        #expect(
            commands.first(where: id(.layoutRestore(try LayoutName("uno"))))?.subtitle
                == "— 2 paneles, retoma 1 sesión de Claude")
    }

    @Test func saveCommandUsesQueryAsName() throws {
        let save = search("solen-dev").first(where: id(.layoutSave(try LayoutName("solen-dev"))))

        #expect(save?.title == "Guardar layout actual como “solen-dev”")
        #expect(save?.group == .workspaces)
    }

    @Test(arguments: ["", "   ", "a/b"])
    func saveCommandNeedsAValidName(query: String) {
        #expect(!search(query).contains { $0.id.namedLayout != nil && $0.title.hasPrefix("Guardar") })
    }

    @Test func savedLayoutsAreFoundByName() throws {
        let found = search("rizaria", saved: [try summary("rizaria-full", panes: 4, agents: 2)])

        #expect(found.first?.id == .layoutRestore(try LayoutName("rizaria-full")))
    }

    @Test func commandIDsRoundTripTheName() throws {
        let name = try LayoutName("solen dev")

        #expect(CommandID.layoutSave(name).namedLayout == .save(name))
        #expect(CommandID.layoutRestore(name).namedLayout == .restore(name))
        #expect(CommandID.paneNew.namedLayout == nil)
    }

    @Test func layoutQueryStillListsTheThreeLayoutsFirst() {
        let firstThree = search("lay").prefix(3).map(\.id)

        #expect(Set(firstThree) == [.layoutDwindle, .layoutColumns, .layoutMaster])
    }

    // MARK: F7 · Shared layouts

    @Test func catalogOffersExportRightAfterEachRestore() throws {
        let commands = CommandCatalog.commands(
            for: CatalogState(
                workspaces: set,
                savedLayouts: [try summary("a", panes: 1, agents: 0), try summary("b", panes: 2, agents: 0)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        let ids = commands.map(\.id)
        let restoreA = try #require(ids.firstIndex(of: .layoutRestore(try LayoutName("a"))))
        #expect(ids[restoreA + 1] == .layoutExport(try LayoutName("a")))
        let export = commands.first(where: id(.layoutExport(try LayoutName("b"))))
        #expect(export?.title == "Exportar layout “b”…")
        #expect(export?.group == .workspaces)
    }

    @Test func catalogOffersImport() {
        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard, layouts: .standard, texts: .spanish)

        let importCommand = commands.first(where: id(.layoutImport))
        #expect(importCommand?.title == "Importar layout…")
        #expect(importCommand?.group == .workspaces)
    }

    @Test func importIsAStandardCommand() {
        #expect(CommandID.allStandard.contains(.layoutImport))
        #expect(CommandID.layoutImport.rawValue == "layout.import")
    }

    @Test func layoutExportRoundTripsThroughCommandID() throws {
        let name = try LayoutName("solen dev")

        #expect(CommandID.layoutExport(name).rawValue == "layout.export:solen dev")
        #expect(CommandID.layoutExport(name).namedLayout == .export(name))
    }

    @Test func exportIsNeverMarkedCurrent() throws {
        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: set, savedLayouts: [try summary("a", panes: 1, agents: 0)]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        #expect(commands.first(where: id(.layoutExport(try LayoutName("a"))))?.isCurrent == false)
    }
}
