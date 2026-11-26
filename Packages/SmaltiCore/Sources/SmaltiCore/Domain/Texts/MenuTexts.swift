/// F7.7: the menu bar's words (F4.5). Items take `titles` first, then the palette's shared titles.
public struct MenuTexts: Sendable, Equatable {
    public let menus: [MenuID: String]
    public let titles: [CommandID: String]
    public let system: [SystemMenuAction: String]
    public let layoutSubmenu: String
    public let scrollingSubmenu: String
    public let paneSubmenu: String
    public let workspaceSubmenu: String
    public let pane: TextTemplate
    public let namedPane: TextTemplate
    /// The direction as it ends "Enfocar hacia …" in the Ventana menu.
    public let directions: [Direction: String]
    public let focusToward: TextTemplate
    public let swapToward: TextTemplate
    public let resizeToward: TextTemplate
    public let commands: CommandTexts

    public static let spanish = MenuTexts(
        menus: [.app: "Smalti", .file: "Archivo", .edit: "Edición", .view: "Ver", .window: "Ventana", .help: "Ayuda"],
        titles: [
            .paneNew: "Nuevo panel", .paneClose: "Cerrar panel", .workspaceNew: "Nuevo workspace",
            .workspaceClose: "Cerrar workspace", .configReload: "Recargar configuración",
            .historySearch: "Buscar en el historial", .paletteOpen: "Paleta de comandos",
            .observatoryToggle: "Observatorio", .panesEqualize: "Igualar paneles", .processesToggle: "Procesos",
            .portsToggle: "Puertos", .timelineToggle: "Timeline",
            .agentJump: "Ir al agente que espera", .workspaceRename: "Renombrar workspace…",
            .guardApprove: "Aprobar comando que espera", .guardReject: "Rechazar comando que espera",
        ],
        system: [
            .services: "Servicios", .hide: "Ocultar Smalti", .hideOthers: "Ocultar otros", .showAll: "Mostrar todo",
            .quit: "Salir de Smalti", .zoom: "Zoom", .bringAllToFront: "Traer todo al frente",
        ],
        layoutSubmenu: "Layout", scrollingSubmenu: "Desplazamiento", paneSubmenu: "Panel",
        workspaceSubmenu: "Workspace",
        pane: "Panel {number}", namedPane: "Panel {number} · {name}",
        directions: [.left: "la izquierda", .right: "la derecha", .up: "arriba", .down: "abajo"],
        focusToward: "Enfocar hacia {direction}", swapToward: "Intercambiar hacia {direction}",
        resizeToward: "Agrandar hacia {direction}", commands: .spanish)

    public static let english = MenuTexts(
        menus: [.app: "Smalti", .file: "File", .edit: "Edit", .view: "View", .window: "Window", .help: "Help"],
        titles: [
            .paneNew: "New Pane", .paneClose: "Close Pane", .workspaceNew: "New Workspace",
            .workspaceClose: "Close Workspace", .configReload: "Reload Configuration",
            .historySearch: "Search History", .paletteOpen: "Command Palette", .observatoryToggle: "Observatory",
            .processesToggle: "Processes",
            .portsToggle: "Ports", .timelineToggle: "Timeline",
            .panesEqualize: "Equalize Panes", .agentJump: "Go to the Waiting Agent",
            .workspaceRename: "Rename Workspace…", .guardApprove: "Approve Waiting Command",
            .guardReject: "Reject Waiting Command",
        ],
        system: [
            .services: "Services", .hide: "Hide Smalti", .hideOthers: "Hide Others", .showAll: "Show All",
            .quit: "Quit Smalti", .zoom: "Zoom", .bringAllToFront: "Bring All to Front",
        ],
        layoutSubmenu: "Layout", scrollingSubmenu: "Scrolling", paneSubmenu: "Pane", workspaceSubmenu: "Workspace",
        pane: "Pane {number}", namedPane: "Pane {number} · {name}",
        directions: [.left: "Left", .right: "Right", .up: "Up", .down: "Down"],
        focusToward: "Focus {direction}", swapToward: "Swap {direction}", resizeToward: "Grow {direction}",
        commands: .english)
}
