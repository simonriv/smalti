import SmaltiCore
import Testing

@Suite("MenuModel")
struct MenuModelTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private func workspaces(_ count: Int = 1, panes: Int = 2) -> WorkspaceSet {
        let all = (0..<count).map { index in
            (0..<panes).reduce(Workspace.empty(name: "w\(index)", rootDirectory: root, layout: DwindleLayout())) {
                workspace, _ in workspace.adding(Pane(id: PaneID(), workingDirectory: root))
            }
        }
        return all.dropFirst().reduce(WorkspaceSet(first: all[0])) { $0.adding($1) }
    }

    private func bar(
        keymap: Keymap = .standard, workspaces set: WorkspaceSet? = nil, checked: Set<CommandID> = [],
        context: KeyContext = .unrestricted
    ) -> MenuBar {
        let set = set ?? workspaces()
        return MenuModel.bar(
            keymap: keymap,
            commands: CommandCatalog.commands(
                for: CatalogState(workspaces: set), keymap: keymap, layouts: .standard, texts: .spanish),
            state: MenuState(workspaces: set, checked: checked, context: context), texts: .spanish)
    }

    private func item(_ title: String, in menu: String, of bar: MenuBar) -> MenuItem? {
        bar.menus.first { $0.title == menu }?.items.flattened.first { $0.title == title }
    }

    /// Mutation (F4.5): what each kind of item is, enabled and checked by default.
    @Test func systemItemsSubmenusAndWorkspacesAreEnabledAndUnchecked() {
        let menus = bar(workspaces: workspaces(2))

        #expect(item("Ocultar Smalti", in: "Smalti", of: menus)?.isEnabled == true)
        #expect(item("Ocultar Smalti", in: "Smalti", of: menus)?.isChecked == false)
        #expect(item("Layout", in: "Ver", of: menus)?.isEnabled == true)
        #expect(item("w1", in: "Ventana", of: menus)?.isEnabled == true)
    }

    @Test func everyContextMenuItemIsEnabled() {
        let items = MenuModel.contextMenu(keymap: .standard, texts: .spanish).filter { !$0.isSeparator }

        #expect(items.allSatisfy { $0.isEnabled })
    }

    @Test func onlyAnEmptyItemIsASeparator() {
        let titled = MenuItem(title: "x", action: nil, chord: nil, isEnabled: true, children: [])
        let untitledCommand = MenuItem(title: "", action: .command(.paneNew), chord: nil, isEnabled: true, children: [])
        let untitledSubmenu = MenuItem(title: "", action: nil, chord: nil, isEnabled: true, children: [titled])

        #expect(MenuItem.separator.isSeparator)
        #expect(!MenuItem.separator.isEnabled)
        #expect(!titled.isSeparator)
        #expect(!untitledCommand.isSeparator)
        #expect(!untitledSubmenu.isSeparator)
    }

    /// Block 4 review: the app finds Edición, Ventana and Ayuda by identity, not by their titles.
    @Test func menusHaveIdentities() {
        #expect(bar().menus.map(\.id) == [.app, .file, .edit, .view, .window, .help])
    }

    @Test func menuOrderMatchesSpec() {
        let menus = bar().menus

        #expect(menus.map(\.title) == ["Smalti", "Archivo", "Edición", "Ver", "Ventana", "Ayuda"])
        #expect(
            menus[1].items.map(\.title) == [
                "Nueva ventana", "Nuevo panel", "Nuevo workspace", "", "Proyectos recientes…",
                "Guardar layout del proyecto", "", "Cerrar panel", "Cerrar workspace", "Cerrar ventana",
            ])
        #expect(
            menus[2].items.map(\.title) == [
                "Copiar", "Pegar", "Seleccionar todo", "", "Buscar…", "Buscar siguiente", "Buscar anterior", "",
                "Limpiar pantalla", "Buscar en el historial",
            ])
        #expect(
            menus[3].items.map(\.title) == [
                "Paleta de comandos", "Observatorio", "Filtrar el Observatorio", "Buscar sesiones de agentes",
                "Importar layout…", "", "Procesos", "Puertos", "Detener el proceso elegido",
                "Bajar la prioridad del proceso elegido", "Ver procesos en árbol",
                "Cambiar el orden de procesos y puertos", "",
                "Layout", "Igualar paneles", "", "Aumentar letra", "Reducir letra", "Tamaño real", "", "Desplazamiento",
                "Abrir en Quick Look", "Abrir Neovim junto al agente", "Abrir en Neovim el último archivo editado", "",
                "Pantalla completa",
            ])
        #expect(
            menus[5].items.map(\.title) == [
                "Ayuda de Smalti", "Bienvenida a Smalti", "Abrir la documentación", "Abrir la política de privacidad",
                "",
                "Reportar un problema o una idea…",
                "Mostrar registros…", "", "Apoyar Smalti…",
            ])
    }

    @Test func smaltiMenuHasTheAppItems() {
        #expect(
            bar().menus[0].items.map(\.title) == [
                "Acerca de Smalti", "", "Apariencia…", "Estudio de prompt…", "Abrir config.toml",
                "Recargar configuración",
                "", "Entrada de teclado segura", "",
                "Servicios", "", "Ocultar Smalti", "Ocultar otros", "Mostrar todo", "", "Salir de Smalti",
            ])
        #expect(item("Salir de Smalti", in: "Smalti", of: bar())?.action == .system(.quit))
        #expect(item("Ocultar otros", in: "Smalti", of: bar())?.chord == (try? KeyChord.parse("cmd+opt+h")))
    }

    /// C1: every command with a chord in the keymap shows it in the menu it belongs to.
    @Test func everyBoundCommandIsInMenuWithItsChord() {
        let items = bar().menus.flatMap { $0.items.flattened }
        let shown = Dictionary(items.compactMap { item in item.command.map { ($0, item.chord) } }) { first, _ in first }
        let bound = CommandID.allStandard.filter { Keymap.standard.chord(for: $0) != nil }
        // Numbered shortcuts appear for the panes and workspaces that exist (2 panes, 1 workspace here); ⌘P only
        // acts inside the observatory.
        let absent = [CommandID.observatoryPeriod] + (3...9).map(CommandID.paneFocus) + (2...9).map(CommandID.workspace)
        let inMenu = bound.filter { !absent.contains($0) }

        for command in inMenu {
            #expect(shown[command] == Keymap.standard.chord(for: command), "\(command.rawValue)")
        }
    }

    @Test func menuShowsReboundChord() throws {
        let keymap = try Keymap.standard.overriding([
            try KeyChord.parse("cmd+f"): nil, try KeyChord.parse("ctrl+cmd+f"): .searchOpen,
        ])

        #expect(item("Buscar…", in: "Edición", of: bar(keymap: keymap))?.chord == (try KeyChord.parse("ctrl+cmd+f")))
    }

    @Test func menuShowsNoChordWhenUnbound() throws {
        let keymap = try Keymap.standard.overriding([try KeyChord.parse("ctrl+cmd+f"): .searchOpen])

        #expect(item("Pantalla completa", in: "Ver", of: bar(keymap: keymap))?.chord == nil)
    }

    @Test func closeWorkspaceDisabledWithOneWorkspace() {
        #expect(item("Cerrar workspace", in: "Archivo", of: bar())?.isEnabled == false)
        #expect(item("Cerrar workspace", in: "Archivo", of: bar(workspaces: workspaces(2)))?.isEnabled == true)
    }

    @Test func terminalItemsDisabledWithoutPanes() {
        #expect(item("Copiar", in: "Edición", of: bar(workspaces: workspaces(panes: 0)))?.isEnabled == false)
        #expect(item("Nueva ventana", in: "Archivo", of: bar(workspaces: workspaces(panes: 0)))?.isEnabled == true)
    }

    @Test func workspaceSubmenuListsEachWorkspaceByNumber() {
        let submenu = bar(workspaces: workspaces(3)).menus[4].items.first { $0.title == "Workspace" }

        #expect(submenu?.children.map(\.title) == ["w0", "w1", "w2", "", "Renombrar workspace…"])
        #expect(submenu?.children.first?.chord == (try? KeyChord.parse("ctrl+1")))
    }

    @Test func paneSubmenuStartsWithTheNumberedPanes() {
        let submenu = bar().menus[4].items.first { $0.title == "Panel" }

        #expect(submenu?.children.prefix(3).map(\.title) == ["Panel 1", "Panel 2", ""])
        #expect(submenu?.children.first?.chord == (try? KeyChord.parse("cmd+1")))
    }

    @Test func layoutSubmenuMarksNothingButListsLayouts() {
        let submenu = bar().menus[3].items.first { $0.title == "Layout" }

        #expect(submenu?.children.map(\.title) == ["Dwindle", "Columnas", "Maestro + pila"])
    }

    @Test func secureInputItemShowsItsCheckmark() {
        #expect(item("Entrada de teclado segura", in: "Smalti", of: bar())?.isChecked == false)
        #expect(
            item("Entrada de teclado segura", in: "Smalti", of: bar(checked: [.secureInputToggle]))?.isChecked == true)
    }

    /// Final review: the menu follows the same rules as the keyboard (an overlay, the resume screen).
    @Test func itemsTheKeyContextDoesNotAllowAreDisabled() {
        let resume = bar(context: KeyContext(allowing: [.windowNew]))

        #expect(item("Nueva ventana", in: "Archivo", of: resume)?.isEnabled == true)
        #expect(item("Nuevo panel", in: "Archivo", of: resume)?.isEnabled == false)
        #expect(item("Cerrar ventana", in: "Archivo", of: resume)?.isEnabled == false)
        #expect(item("Paleta de comandos", in: "Ver", of: resume)?.isEnabled == false)
    }

    @Test func aSystemChordReboundInTheTOMLLeavesTheSystemItem() throws {
        let keymap = try Keymap.standard.overriding([try KeyChord.parse("cmd+h"): .helpShow])

        #expect(item("Ocultar Smalti", in: "Smalti", of: bar(keymap: keymap))?.chord == nil)
        #expect(item("Salir de Smalti", in: "Smalti", of: bar(keymap: keymap))?.chord == (try KeyChord.parse("cmd+q")))
    }

    @Test func contextMenuMatchesSpec() {
        #expect(
            MenuModel.contextMenu(keymap: .standard, texts: .spanish).map(\.title) == [
                "Copiar", "Pegar", "Seleccionar todo", "", "Buscar…", "Limpiar pantalla", "", "Nuevo panel",
                "Cerrar panel",
            ])
    }

    @Test func dockMenuHasNewWindow() {
        #expect(MenuModel.dockMenu(texts: .spanish).map(\.title) == ["Nueva ventana"])
        #expect(MenuModel.dockMenu(texts: .spanish).first?.command == .windowNew)
    }

    /// F7: importing a layout is in the View menu, next to the session search.
    @Test func viewMenuOffersLayoutImport() {
        #expect(item("Importar layout…", in: "Ver", of: bar())?.action == .command(.layoutImport))
    }
}
