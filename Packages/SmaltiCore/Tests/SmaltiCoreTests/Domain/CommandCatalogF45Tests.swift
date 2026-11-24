import SmaltiCore
import Testing

@Suite("CommandCatalog · F4.5")
struct CommandCatalogF45Tests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private func workspaces(panes: Int) -> WorkspaceSet {
        let workspace = (0..<panes).reduce(Workspace.empty(name: "p", rootDirectory: root, layout: DwindleLayout())) {
            workspace, _ in workspace.adding(Pane(id: PaneID(), workingDirectory: root))
        }
        return WorkspaceSet(first: workspace)
    }

    private func commands(panes: Int) -> [Command] {
        CommandCatalog.commands(for: workspaces(panes: panes), keymap: .standard, layouts: .standard)
    }

    @Test(arguments: [
        (CommandID.windowNew, "Nueva ventana", CommandGroup.windows), (.windowClose, "Cerrar ventana", .windows),
        (.windowFullscreen, "Pantalla completa", .windows), (.windowMinimize, "Minimizar", .windows),
        (.terminalCopy, "Copiar", .terminal), (.terminalPaste, "Pegar", .terminal),
        (.terminalSelectAll, "Seleccionar todo", .terminal), (.terminalClear, "Limpiar pantalla", .terminal),
        (.searchOpen, "Buscar…", .terminal), (.searchNext, "Buscar siguiente", .terminal),
        (.searchPrevious, "Buscar anterior", .terminal), (.fontIncrease, "Aumentar letra", .terminal),
        (.fontDecrease, "Reducir letra", .terminal), (.fontReset, "Tamaño real", .terminal),
        (.scrollPageUp, "Página arriba", .terminal), (.scrollPageDown, "Página abajo", .terminal),
        (.scrollTop, "Al principio", .terminal), (.scrollBottom, "Al final", .terminal),
        (.promptPrevious, "Prompt anterior", .terminal), (.promptNext, "Prompt siguiente", .terminal),
        (.configOpen, "Configuración…", .configuration),
        (.secureInputToggle, "Entrada de teclado segura", .configuration),
        (.helpShow, "Ayuda de Smalti", .help), (.feedbackReport, "Reportar un problema o una idea…", .help),
        (.logsShow, "Mostrar registros…", .help), (.appAbout, "Acerca de Smalti", .help),
    ])
    func newCommandsAreOfferedWithTheirTitles(_ id: CommandID, _ title: String, _ group: CommandGroup) throws {
        let command = try #require(commands(panes: 1).first { $0.id == id })

        #expect(command.title == title)
        #expect(command.group == group)
        #expect(command.shortcut == Keymap.standard.chord(for: id))
    }

    @Test func terminalCommandsNeedAPane() {
        let ids = Set(commands(panes: 0).map(\.id))

        #expect(!ids.contains(.terminalCopy))
        #expect(!ids.contains(.searchOpen))
        #expect(ids.contains(.windowNew))
        #expect(ids.contains(.helpShow))
    }

    @Test func newGroupsHaveTheirNames() {
        #expect(CommandGroup.windows.rawValue == "Ventanas")
        #expect(CommandGroup.terminal.rawValue == "Terminal")
        #expect(CommandGroup.help.rawValue == "Ayuda")
    }
}
