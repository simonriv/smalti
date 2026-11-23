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
        SearchCommands(layouts: .standard).execute(query, set: set, keymap: .standard, savedLayouts: saved)
            .map(\.command)
    }

    @Test func catalogListsSavedLayoutsWithSubtitle() throws {
        let commands = CommandCatalog.commands(
            for: set, keymap: .standard, layouts: .standard,
            savedLayouts: [try summary("rizaria-full", panes: 4, agents: 2)])

        let restore = commands.first(where: id(.layoutRestore(try LayoutName("rizaria-full"))))
        #expect(restore?.title == "Restaurar layout “rizaria-full”")
        #expect(restore?.subtitle == "— 4 paneles, retoma 2 sesiones de Claude")
        #expect(restore?.group == .workspaces)
    }

    @Test func catalogOmitsAgentClauseWithoutAgents() throws {
        let commands = CommandCatalog.commands(
            for: set, keymap: .standard, layouts: .standard, savedLayouts: [try summary("solo", panes: 1, agents: 0)])

        #expect(commands.first(where: id(.layoutRestore(try LayoutName("solo"))))?.subtitle == "— 1 panel")
    }

    @Test func oneAgentIsSingular() throws {
        let commands = CommandCatalog.commands(
            for: set, keymap: .standard, layouts: .standard, savedLayouts: [try summary("uno", panes: 2, agents: 1)])

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
}
