import SmaltiCore
import Testing

@Suite("CommandCatalog")
struct CommandCatalogTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/Users/s")
    }

    private func makeWorkspace(name: String = "w", paneCount: Int = 0, layout: any LayoutStrategy = DwindleLayout())
        -> Workspace
    {
        (0..<paneCount).reduce(Workspace.empty(name: name, rootDirectory: root, layout: layout)) { workspace, _ in
            workspace.adding(Pane(id: PaneID(), workingDirectory: root))
        }
    }

    private func commands(for set: WorkspaceSet) -> [Command] {
        CommandCatalog.commands(for: set, keymap: .standard, layouts: .standard)
    }

    private func commands(paneCount: Int) -> [Command] {
        commands(for: WorkspaceSet(first: makeWorkspace(paneCount: paneCount)))
    }

    @Test func layoutCommandsComeFromTheLayoutCatalog() {
        let titles = commands(paneCount: 0).filter { $0.group == .tiling }.map(\.title)

        #expect(titles.prefix(3) == ["Layout: Dwindle", "Layout: Columnas", "Layout: Maestro + pila"])
    }

    @Test func dwindleCarriesItsSubtitle() throws {
        let dwindle = try #require(commands(paneCount: 0).first { $0.id == .layoutDwindle })

        #expect(dwindle.subtitle == "cada panel nuevo divide el último")
    }

    @Test func currentLayoutIsMarked() {
        let set = WorkspaceSet(first: makeWorkspace(layout: ColumnsLayout()))

        let current = commands(for: set).filter(\.isCurrent).map(\.id)

        #expect(current == [.layoutColumns])
    }

    @Test func equalizeHiddenWithOnePane() {
        #expect(!commands(paneCount: 1).contains { $0.id == .panesEqualize })
    }

    @Test func equalizeShownWithTwoPanes() {
        #expect(commands(paneCount: 2).contains { $0.id == .panesEqualize })
    }

    @Test func closePaneHiddenWithoutPanes() {
        #expect(!commands(paneCount: 0).contains { $0.id == .paneClose })
        #expect(commands(paneCount: 1).contains { $0.id == .paneClose })
    }

    @Test func directionalCommandsNeedTwoPanes() {
        let directional = { (paneCount: Int) in
            commands(paneCount: paneCount).filter { $0.title.contains("hacia") }.count
        }

        #expect(directional(1) == 0)
        #expect(directional(2) == 12)
    }

    @Test func directionalTitlesUseSpanishDirections() {
        let titles = commands(paneCount: 2).map(\.title)

        #expect(titles.contains("Enfocar panel hacia la izquierda"))
        #expect(titles.contains("Intercambiar panel hacia arriba"))
        #expect(titles.contains("Agrandar panel hacia la derecha"))
        #expect(titles.contains("Enfocar panel hacia abajo"))
    }

    @Test func closeWorkspaceHiddenWithOneWorkspace() {
        let one = commands(paneCount: 0)
        let two = commands(for: WorkspaceSet(first: makeWorkspace()).adding(makeWorkspace()))

        #expect(!one.contains { $0.id == .workspaceClose })
        #expect(two.contains { $0.id == .workspaceClose })
    }

    @Test func goToWorkspaceListsOnlyInactiveOnes() throws {
        let inactive = makeWorkspace(name: "api")
        let set = WorkspaceSet(first: inactive).adding(makeWorkspace(name: "web"))

        let goTo = commands(for: set).filter { $0.title.hasPrefix("Ir a workspace") }

        #expect(goTo.map(\.title) == ["Ir a workspace api"])
        #expect(goTo.map(\.id) == [.workspaceGo(inactive.id)])
    }

    @Test func noPaneCommandsWithoutPanes() {
        let paneOnly = commands(paneCount: 0).filter { $0.group == .panes }.map(\.id)

        #expect(paneOnly == [.paneNew])
    }

    @Test func noGoToWorkspaceWithSingleWorkspace() {
        #expect(!commands(paneCount: 0).contains { $0.title.hasPrefix("Ir a workspace") })
    }

    @Test func commandsCarryKeymapShortcut() throws {
        let columns = try #require(commands(paneCount: 0).first { $0.id == .layoutColumns })

        #expect(columns.shortcut?.display == "⌥⌘C")
    }

    @Test func unboundCommandHasNoShortcut() throws {
        let reload = try #require(commands(paneCount: 0).first { $0.id == .configReload })

        #expect(reload.shortcut == nil)
    }

    @Test func goToPaneShowsTheProcessAsSubtitle() throws {
        let pane = Pane(id: PaneID(), workingDirectory: root).applying(.foregroundProcessChanged("claude"))
        let set = WorkspaceSet(first: makeWorkspace().adding(pane))

        let goTo = try #require(commands(for: set).first { $0.id == .paneFocus(1) })

        #expect(goTo.title == "Ir al panel 1")
        #expect(goTo.subtitle == "claude")
        #expect(goTo.shortcut?.display == "⌘1")
    }

    @Test func paneCommandsStopAtNine() {
        let numbered = commands(paneCount: 12).filter { $0.title.hasPrefix("Ir al panel") }

        #expect(numbered.count == 9)
        #expect(numbered.last?.title == "Ir al panel 9")
    }

    @Test func reloadConfigurationShowsTheConfigPath() throws {
        let reload = try #require(commands(paneCount: 0).first { $0.id == .configReload })

        #expect(reload.title == "Recargar configuración")
        #expect(reload.subtitle == "~/.config/smalti/config.toml")
        #expect(reload.group == .configuration)
    }

    @Test func groupsAppearInDisplayOrder() {
        let groups = commands(for: WorkspaceSet(first: makeWorkspace(paneCount: 2)).adding(makeWorkspace())).map(
            \.group)

        #expect(groups == groups.sorted { Self.order($0) < Self.order($1) })
    }

    private static func order(_ group: CommandGroup) -> Int {
        [CommandGroup.tiling, .panes, .workspaces, .configuration].firstIndex(of: group) ?? 0
    }
}
