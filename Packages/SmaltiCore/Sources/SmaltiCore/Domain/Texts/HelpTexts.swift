/// F7.7: the help view's words (⌘?). Rows without their own title here take the palette's shared one.
public struct HelpTexts: Sendable, Equatable {
    /// The keys of a command without a chord: "en ⌘K", with the palette's chord in effect.
    public let inPalette: TextTemplate
    public let sections: [HelpSectionID: String]
    public let titles: [CommandID: String]
    public let goToWorkspaces: String
    public let goToPanes: String
    public let focusPanes: String
    public let swapPanes: String
    public let resizePanes: String
    public let complete: String
    public let acceptSuggestion: String
    public let searchHistory: String
    public let openLink: String
    public let openLinkKeys: String
    public let pastePath: String
    public let pastePathKeys: String
    public let terminalMenu: String
    public let terminalMenuKeys: String
    public let confirmClose: String
    /// F7.7: what leaves the Mac and what stays, one sentence per line.
    public let privacyLines: [String]
    public let commands: CommandTexts

    public static let spanish = HelpTexts(
        inPalette: "en {palette}",
        sections: [
            .windows: "Ventanas y workspaces", .panes: "Paneles", .terminal: "Terminal", .search: "Buscar",
            .tiling: "Tiling", .agents: "Agentes y observatorio", .prompt: "En el prompt", .mouse: "Ratón",
            .configuration: "Configuración y ayuda", .privacy: "Privacidad",
        ],
        titles: [
            .workspaceNew: "Nuevo workspace", .workspaceRename: "Renombrar workspace…",
            .workspaceClose: "Cerrar workspace", .layoutImport: "Importar layout…", .paneNew: "Nuevo panel",
            .paneClose: "Cerrar panel", .panesEqualize: "Igualar paneles", .agentJump: "Saltar al agente que espera",
            .observatoryToggle: "Abrir observatorio", .observatoryPeriod: "Cambiar el periodo del observatorio",
            .claudeIntegrationInstall: "Instalar integración con Claude Code",
            .claudeIntegrationUninstall: "Desinstalar integración con Claude Code",
            .guardApprove: "Aprobar el comando que espera en el panel",
            .guardReject: "Rechazar el comando que espera en el panel",
            .secretsProtect: "Proteger los secretos del proyecto",
            .secretsUnprotect: "Quitar la protección de secretos del proyecto", .paletteOpen: "Paleta de comandos",
            .configReload: "Recargar configuración",
            .updatesAutomatic: "Activar o desactivar actualizaciones automáticas",
        ],
        goToWorkspaces: "Ir al workspace 1–9", goToPanes: "Ir al panel 1–9", focusPanes: "Enfocar panel hacia…",
        swapPanes: "Intercambiar panel hacia…", resizePanes: "Agrandar panel hacia…", complete: "Completar",
        acceptSuggestion: "Aceptar sugerencia", searchHistory: "Buscar en el historial", openLink: "Abrir un enlace",
        openLinkKeys: "⌘clic", pastePath: "Pegar la ruta de un archivo", pastePathKeys: "arrastrar",
        terminalMenu: "Menú del terminal", terminalMenuKeys: "clic derecho",
        confirmClose: "No preguntar al cerrar con procesos",
        privacyLines: [
            "Nada sale de tu Mac salvo la comprobación de actualizaciones (el appcast de smalti.sh).",
            "La telemetría de Claude Code se recibe en 127.0.0.1 y no sale de tu Mac.",
            "Ollama se consulta en 127.0.0.1 y las sesiones de otros agentes solo se leen.",
            "Reportar un problema abre GitHub en tu navegador: nada se envía hasta que lo publicas.",
        ],
        commands: .spanish)

    public static let english = HelpTexts(
        inPalette: "in {palette}",
        sections: [
            .windows: "Windows and Workspaces", .panes: "Panes", .terminal: "Terminal", .search: "Find",
            .tiling: "Tiling", .agents: "Agents and Observatory", .prompt: "At the Prompt", .mouse: "Mouse",
            .configuration: "Configuration and Help", .privacy: "Privacy",
        ],
        titles: [
            .workspaceNew: "New Workspace", .workspaceRename: "Rename Workspace…", .workspaceClose: "Close Workspace",
            .layoutImport: "Import Layout…", .paneNew: "New Pane", .paneClose: "Close Pane",
            .panesEqualize: "Equalize Panes", .agentJump: "Jump to the Waiting Agent",
            .observatoryToggle: "Open Observatory", .observatoryPeriod: "Change the Observatory Period",
            .claudeIntegrationInstall: "Install Claude Code Integration",
            .claudeIntegrationUninstall: "Uninstall Claude Code Integration",
            .guardApprove: "Approve the Command Waiting in the Pane",
            .guardReject: "Reject the Command Waiting in the Pane", .secretsProtect: "Protect the Project’s Secrets",
            .secretsUnprotect: "Remove the Project’s Secret Protection", .paletteOpen: "Command Palette",
            .configReload: "Reload Configuration", .updatesAutomatic: "Turn Automatic Updates On or Off",
        ],
        goToWorkspaces: "Go to Workspace 1–9", goToPanes: "Go to Pane 1–9", focusPanes: "Focus Pane in a Direction",
        swapPanes: "Swap Pane in a Direction", resizePanes: "Grow Pane in a Direction", complete: "Complete",
        acceptSuggestion: "Accept Suggestion", searchHistory: "Search History", openLink: "Open a Link",
        openLinkKeys: "⌘-click", pastePath: "Paste a File’s Path", pastePathKeys: "drag",
        terminalMenu: "Terminal Menu", terminalMenuKeys: "right-click",
        confirmClose: "Don’t Ask When Closing with Processes",
        privacyLines: [
            "Nothing leaves your Mac except the update check (smalti.sh’s appcast).",
            "Claude Code’s telemetry is received on 127.0.0.1 and never leaves your Mac.",
            "Ollama is asked on 127.0.0.1, and other agents’ sessions are only read.",
            "Reporting a problem opens GitHub in your browser: nothing is sent until you post it.",
        ],
        commands: .english)
}

/// The help view's sections, in order.
public enum HelpSectionID: CaseIterable, Hashable, Sendable {
    case windows, panes, terminal, search, tiling, agents, prompt, mouse, configuration, privacy
}
