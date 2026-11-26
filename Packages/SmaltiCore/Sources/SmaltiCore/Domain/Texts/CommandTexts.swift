/// F7.7: the palette's words. `titles` are shared with the menus and the help (F4.5); `paletteTitles` are the
/// palette's own wording for commands the menus name differently.
public struct CommandTexts: Sendable, Equatable {
    public let titles: [CommandID: String]
    public let paletteTitles: [CommandID: String]
    public let groups: [CommandGroup: String]
    public let layoutNames: [LayoutID: String]
    /// One line under a layout's command, only where the name does not say enough.
    public let layoutSubtitles: [LayoutID: String]
    public let layoutTitle: TextTemplate
    /// The direction as it ends "Enfocar panel hacia …".
    public let directions: [Direction: String]
    public let focusPane: TextTemplate
    public let swapPane: TextTemplate
    public let resizePane: TextTemplate
    public let goToPane: TextTemplate
    public let goToWorkspace: TextTemplate
    public let turnOffAutomaticUpdates: String
    public let turnOnAutomaticUpdates: String
    public let saveLayout: TextTemplate
    public let restoreLayout: TextTemplate
    public let restoreNewerFormat: TextTemplate
    public let restorePanes: PluralText
    public let restoreSessions: PluralText
    public let exportLayout: TextTemplate
    public let approve: TextTemplate
    public let reject: TextTemplate
    public let protectSecrets: TextTemplate
    public let unprotectSecrets: TextTemplate
    public let editedFileSubtitle: TextTemplate
    public let integrations: IntegrationTexts
    public let time: TimeTexts
    public let guards: GuardTexts
    /// The started title of a GitHub issue: "Fallo: " / "Idea: ".
    public let feedbackTitles: [FeedbackKind: String]

    public static let spanish = CommandTexts(
        titles: [
            .windowNew: "Nueva ventana", .windowClose: "Cerrar ventana", .windowFullscreen: "Pantalla completa",
            .windowMinimize: "Minimizar", .terminalCopy: "Copiar", .terminalPaste: "Pegar",
            .terminalSelectAll: "Seleccionar todo", .terminalClear: "Limpiar pantalla", .searchOpen: "Buscar…",
            .searchNext: "Buscar siguiente", .searchPrevious: "Buscar anterior", .fontIncrease: "Aumentar letra",
            .fontDecrease: "Reducir letra", .fontReset: "Tamaño real", .scrollPageUp: "Página arriba",
            .scrollPageDown: "Página abajo", .scrollTop: "Al principio", .scrollBottom: "Al final",
            .promptPrevious: "Prompt anterior", .promptNext: "Prompt siguiente", .configOpen: "Abrir config.toml",
            .secureInputToggle: "Entrada de teclado segura", .helpShow: "Ayuda de Smalti",
            .feedbackReport: "Reportar un problema o una idea…", .logsShow: "Mostrar registros…",
            .appAbout: "Acerca de Smalti", .appearanceOpen: "Apariencia…", .promptStudio: "Estudio de prompt…",
            .themeOpen: "Abrir theme.toml", .themeNext: "Siguiente tema", .ansiReset: "Restablecer paleta ANSI",
            .promptApply: "Aplicar prompt a todos los paneles", .promptExport: "Exportar como starship.toml",
            .legibilityToggle: "Proteger legibilidad", .previewQuickLook: "Abrir en Quick Look",
            .harnessSearch: "Buscar sesiones de agentes", .editorOpenBeside: "Abrir Neovim junto al agente",
            .editorOpenLastEdited: "Abrir en Neovim el último archivo editado",
            .observatoryFilter: "Filtrar el Observatorio", .layoutImport: "Importar layout…",
            .updatesCheck: "Buscar actualizaciones…", .helpDocs: "Abrir la documentación",
            .appSupport: "Apoyar Smalti…",
            .helpWelcome: "Bienvenida a Smalti", .helpPrivacy: "Abrir la política de privacidad",
        ],
        paletteTitles: [
            .panesEqualize: "Igualar tamaños de paneles", .paneNew: "Nuevo panel", .paneClose: "Cerrar panel",
            .historySearch: "Buscar en el historial", .agentJump: "Saltar al agente que espera",
            .observatoryToggle: "Abrir observatorio", .workspaceNew: "Nuevo workspace",
            .processesToggle: "Abrir procesos", .portsToggle: "Abrir puertos en uso",
            .processesStop: "Detener el proceso elegido",
            .processesLowerPriority: "Bajar la prioridad del proceso elegido",
            .processesTree: "Ver procesos en árbol", .processesSort: "Cambiar el orden de procesos y puertos",
            .workspaceRename: "Renombrar workspace…", .workspaceClose: "Cerrar workspace",
            .configReload: "Recargar configuración",
        ],
        groups: [
            .approvals: "Esperan tu aprobación", .tiling: "Tiling", .panes: "Paneles",
            .workspaces: "Workspaces y sesiones", .configuration: "Configuración", .windows: "Ventanas",
            .terminal: "Terminal", .help: "Ayuda", .editedFiles: "Editados por Claude",
        ],
        layoutNames: [.dwindle: "Dwindle", .columns: "Columnas", .master: "Maestro + pila"],
        layoutSubtitles: [.dwindle: "cada panel nuevo divide el último"],
        layoutTitle: "Layout: {name}",
        directions: [.left: "la izquierda", .right: "la derecha", .up: "arriba", .down: "abajo"],
        focusPane: "Enfocar panel hacia {direction}", swapPane: "Intercambiar panel hacia {direction}",
        resizePane: "Agrandar panel hacia {direction}", goToPane: "Ir al panel {number}",
        goToWorkspace: "Ir a workspace {name}",
        turnOffAutomaticUpdates: "Desactivar actualizaciones automáticas",
        turnOnAutomaticUpdates: "Activar actualizaciones automáticas",
        saveLayout: "Guardar layout actual como “{name}”", restoreLayout: "Restaurar layout “{name}”",
        restoreNewerFormat: "— guardado por una versión más nueva de Smalti (formato {format})",
        restorePanes: PluralText(one: "— {count} panel", other: "— {count} paneles"),
        restoreSessions: PluralText(
            one: ", retoma {count} sesión de Claude", other: ", retoma {count} sesiones de Claude"),
        exportLayout: "Exportar layout “{name}”…", approve: "Aprobar “{quote}” en {workspace}",
        reject: "Rechazar “{quote}” en {workspace}", protectSecrets: "Proteger secretos en “{name}”",
        unprotectSecrets: "Quitar protección de secretos en “{name}”", editedFileSubtitle: "línea {line} · {elapsed}",
        integrations: .spanish, time: .spanish, guards: .spanish,
        feedbackTitles: [.bug: "Fallo: ", .idea: "Idea: "])

    public static let english = CommandTexts(
        titles: [
            .windowNew: "New Window", .windowClose: "Close Window", .windowFullscreen: "Toggle Full Screen",
            .windowMinimize: "Minimize", .terminalCopy: "Copy", .terminalPaste: "Paste",
            .terminalSelectAll: "Select All", .terminalClear: "Clear Screen", .searchOpen: "Find…",
            .searchNext: "Find Next", .searchPrevious: "Find Previous", .fontIncrease: "Increase Font Size",
            .fontDecrease: "Decrease Font Size", .fontReset: "Actual Size", .scrollPageUp: "Page Up",
            .scrollPageDown: "Page Down", .scrollTop: "Scroll to Top", .scrollBottom: "Scroll to Bottom",
            .promptPrevious: "Previous Prompt", .promptNext: "Next Prompt", .configOpen: "Open config.toml",
            .secureInputToggle: "Secure Keyboard Entry", .helpShow: "Smalti Help",
            .feedbackReport: "Report a Problem or Idea…", .logsShow: "Show Logs…", .appAbout: "About Smalti",
            .appearanceOpen: "Appearance…", .promptStudio: "Prompt Studio…", .themeOpen: "Open theme.toml",
            .themeNext: "Next Theme", .ansiReset: "Reset ANSI Palette", .promptApply: "Apply Prompt to All Panes",
            .promptExport: "Export as starship.toml", .legibilityToggle: "Protect Legibility",
            .previewQuickLook: "Open in Quick Look", .harnessSearch: "Search Agent Sessions",
            .editorOpenBeside: "Open Neovim Beside the Agent",
            .editorOpenLastEdited: "Open the Last Edited File in Neovim", .observatoryFilter: "Filter the Observatory",
            .layoutImport: "Import Layout…", .updatesCheck: "Check for Updates…", .helpDocs: "Open the Documentation",
            .appSupport: "Support Smalti…", .helpWelcome: "Welcome to Smalti", .helpPrivacy: "Open the Privacy Policy",
        ],
        paletteTitles: [
            .panesEqualize: "Equalize Pane Sizes", .paneNew: "New Pane", .paneClose: "Close Pane",
            .historySearch: "Search History", .agentJump: "Jump to the Waiting Agent",
            .observatoryToggle: "Open Observatory", .workspaceNew: "New Workspace",
            .processesToggle: "Open Processes", .portsToggle: "Open Ports in Use",
            .processesStop: "Stop the Selected Process",
            .processesLowerPriority: "Lower the Selected Process’s Priority",
            .processesTree: "Show Processes as a Tree", .processesSort: "Change the Order of Processes and Ports",
            .workspaceRename: "Rename Workspace…", .workspaceClose: "Close Workspace",
            .configReload: "Reload Configuration",
        ],
        groups: [
            .approvals: "Waiting for your approval", .tiling: "Tiling", .panes: "Panes",
            .workspaces: "Workspaces and Sessions", .configuration: "Configuration", .windows: "Windows",
            .terminal: "Terminal", .help: "Help", .editedFiles: "Edited by Claude",
        ],
        layoutNames: [.dwindle: "Dwindle", .columns: "Columns", .master: "Master + Stack"],
        layoutSubtitles: [.dwindle: "each new pane splits the last one"],
        layoutTitle: "Layout: {name}",
        directions: [.left: "Left", .right: "Right", .up: "Up", .down: "Down"],
        focusPane: "Focus Pane {direction}", swapPane: "Swap Pane {direction}", resizePane: "Grow Pane {direction}",
        goToPane: "Go to Pane {number}", goToWorkspace: "Go to Workspace {name}",
        turnOffAutomaticUpdates: "Turn Off Automatic Updates", turnOnAutomaticUpdates: "Turn On Automatic Updates",
        saveLayout: "Save Current Layout as “{name}”", restoreLayout: "Restore Layout “{name}”",
        restoreNewerFormat: "— saved by a newer Smalti (format {format})",
        restorePanes: PluralText(one: "— {count} pane", other: "— {count} panes"),
        restoreSessions: PluralText(
            one: ", resumes {count} Claude session", other: ", resumes {count} Claude sessions"),
        exportLayout: "Export Layout “{name}”…", approve: "Approve “{quote}” in {workspace}",
        reject: "Reject “{quote}” in {workspace}", protectSecrets: "Protect Secrets in “{name}”",
        unprotectSecrets: "Remove Secret Protection in “{name}”", editedFileSubtitle: "line {line} · {elapsed}",
        integrations: .english, time: .english, guards: .english,
        feedbackTitles: [.bug: "Bug: ", .idea: "Idea: "])
}
