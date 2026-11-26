import SmaltiCore
import Testing

/// F5: the appearance and prompt commands in ⌘K, the help and the Smalti menu (spec, "Comandos y atajos nuevos").
@Suite("CommandCatalog · F5")
struct CommandCatalogF5Tests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private var set: WorkspaceSet {
        WorkspaceSet(
            first: Workspace.empty(name: "p", rootDirectory: root, layout: DwindleLayout())
                .adding(Pane(id: PaneID(), workingDirectory: root)))
    }

    private var commands: [Command] {
        CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard, layouts: .standard, texts: .spanish)
    }

    @Test(arguments: [
        (CommandID.appearanceOpen, "Apariencia…"), (.promptStudio, "Estudio de prompt…"),
        (.configOpen, "Abrir config.toml"), (.themeOpen, "Abrir theme.toml"), (.themeNext, "Siguiente tema"),
        (.ansiReset, "Restablecer paleta ANSI"), (.promptApply, "Aplicar prompt a todos los paneles"),
        (.promptExport, "Exportar como starship.toml"), (.legibilityToggle, "Proteger legibilidad"),
    ])
    func everyNewCommandIsInPaletteWithItsTitle(_ id: CommandID, _ title: String) throws {
        let command = try #require(commands.first { $0.id == id })

        #expect(command.title == title)
        #expect(command.group == .configuration)
    }

    @Test func paletteShowsTheNewShortcuts() throws {
        let appearance = try #require(commands.first { $0.id == .appearanceOpen })
        let config = try #require(commands.first { $0.id == .configOpen })

        #expect(appearance.shortcut == (try KeyChord.parse("cmd+,")))
        #expect(config.shortcut == (try KeyChord.parse("opt+cmd+,")))
    }

    @Test(arguments: [
        CommandID.appearanceOpen, .promptStudio, .configOpen, .themeOpen, .themeNext, .ansiReset, .promptApply,
        .promptExport, .legibilityToggle,
    ])
    func everyNewCommandIsInHelp(_ id: CommandID) {
        let covered = HelpCatalog.sections(keymap: .standard, texts: .spanish).flatMap(\.entries).flatMap(\.covers)

        #expect(covered.contains(id))
    }

    @Test func helpListsAppearanceWithItsShortcut() throws {
        let entries = HelpCatalog.sections(keymap: .standard, texts: .spanish).flatMap(\.entries)
        let appearance = try #require(entries.first { $0.command == .appearanceOpen })

        #expect(appearance.title == "Apariencia…")
        #expect(appearance.keys == "⌘,")
    }

    @Test func menuSmaltiListsAppearanceAndStudio() {
        let bar = MenuModel.bar(
            keymap: .standard, commands: commands,
            state: MenuState(workspaces: set, checked: [], context: .unrestricted), texts: .spanish)
        let titles = bar.menus[0].items.map(\.title)

        let appearance = titles.firstIndex(of: "Apariencia…")
        let studio = titles.firstIndex(of: "Estudio de prompt…")
        let config = titles.firstIndex(of: "Abrir config.toml")

        #expect(appearance != nil && studio != nil && config != nil)
        #expect((appearance ?? 0) < (studio ?? 0) && (studio ?? 0) < (config ?? 0))
    }
}
