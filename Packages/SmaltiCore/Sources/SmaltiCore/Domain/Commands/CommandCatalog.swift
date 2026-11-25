import Foundation

/// Builds the commands the palette offers for the current state, in display order.
public enum CommandCatalog {
    private static let configPathSubtitle = "~/.config/smalti/config.toml"

    public static func commands(for state: CatalogState, keymap: Keymap, layouts: LayoutCatalog) -> [Command] {
        let context = Context(workspaces: state.workspaces, keymap: keymap, integrations: state.integrations)
        return state.pendingApprovals.flatMap(approvalCommands)
            + tilingCommands(context, layouts)
            + paneCommands(context)
            + terminalCommands(context)
            + workspaceCommands(context)
            + state.savedLayouts.flatMap { [restoreCommand($0), exportCommand($0)] }
            + windowCommands(context)
            + configurationCommands(context)
            + (state.secretsProject.map { [secretsCommand($0)] } ?? [])
            + helpCommands(context)
            + state.editedFiles.map { editedFileCommand($0, now: state.now) }
    }

    /// F7.5: the longest part of a command an approval entry quotes.
    static let approvalQuoteLength = 40

    /// «Aprobar “terraform destroy” en rizaria» and its «Rechazar…», with the rule and the environment below.
    private static func approvalCommands(_ entry: ApprovalEntry) -> [Command] {
        let subject = entry.approval.subject
        let command = subject.command
        let quote =
            command.count > approvalQuoteLength ? String(command.prefix(approvalQuoteLength)) + "…" : command
        let subtitle = [subject.summary, subject.environment.detail].compactMap { $0 }.joined(separator: " · ")
        return [
            (CommandID.guardApprove(id: entry.approval.id), "Aprobar"),
            (CommandID.guardReject(id: entry.approval.id), "Rechazar"),
        ].map { id, verb in
            Command(
                id: id, title: "\(verb) “\(quote)” en \(entry.workspace)", subtitle: subtitle, group: .approvals,
                shortcut: nil, isCurrent: false)
        }
    }

    /// F7.5: «Proteger secretos en “rizaria”» or its undo, whichever applies.
    private static func secretsCommand(_ project: SecretsProjectState) -> Command {
        let (id, title) =
            project.isProtected
            ? (CommandID.secretsUnprotect, "Quitar protección de secretos en “\(project.name)”")
            : (CommandID.secretsProtect, "Proteger secretos en “\(project.name)”")
        return Command(id: id, title: title, subtitle: nil, group: .configuration, shortcut: nil, isCurrent: false)
    }

    /// "reminder.service.ts", "línea 42 · hace 2 min".
    private static func editedFileCommand(_ file: EditedFile, now: Date) -> Command {
        Command(
            id: .editorOpen(path: file.path, line: file.line), title: file.fileName,
            subtitle: "línea \(file.line) · \(ElapsedPhrase.text(since: file.at, now: now))", group: .editedFiles,
            shortcut: nil, isCurrent: false)
    }

    /// F4.5: titles as in the spec's menu table; the menu and the help reuse them.
    static let titles: [CommandID: String] = [
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
    ]

    static let terminalIDs: [CommandID] = [
        .terminalCopy, .terminalPaste, .terminalSelectAll, .terminalClear, .searchOpen, .searchNext, .searchPrevious,
        .fontIncrease, .fontDecrease, .fontReset, .scrollPageUp, .scrollPageDown, .scrollTop, .scrollBottom,
        .promptPrevious, .promptNext, .previewQuickLook,
    ]

    private static func terminalCommands(_ context: Context) -> [Command] {
        guard context.paneCount >= 1 else { return [] }
        return terminalIDs.map { context.titled($0, group: .terminal) }
    }

    private static func windowCommands(_ context: Context) -> [Command] {
        [CommandID.windowNew, .windowClose, .windowFullscreen, .windowMinimize].map {
            context.titled($0, group: .windows)
        }
    }

    private static func helpCommands(_ context: Context) -> [Command] {
        [CommandID.helpShow, .feedbackReport, .logsShow, .appAbout].map { context.titled($0, group: .help) }
    }

    /// "Guardar layout actual como “solen-dev”", offered for whatever the user typed when it is a valid name.
    public static func saveCommand(named query: String) -> Command? {
        guard let name = try? LayoutName(query) else { return nil }
        return Command(
            id: .layoutSave(name), title: "Guardar layout actual como “\(name.rawValue)”", subtitle: nil,
            group: .workspaces, shortcut: nil, isCurrent: false)
    }

    /// "Restaurar layout “rizaria-full” — 4 paneles, retoma 2 sesiones de Claude" (Paleta.dc.html).
    private static func restoreCommand(_ layout: NamedLayoutSummary) -> Command {
        let panes = "\(layout.paneCount) \(layout.paneCount == 1 ? "panel" : "paneles")"
        let sessions = layout.agentCount == 1 ? "sesión" : "sesiones"
        let agents = layout.agentCount > 0 ? ", retoma \(layout.agentCount) \(sessions) de Claude" : ""
        return Command(
            id: .layoutRestore(layout.name), title: "Restaurar layout “\(layout.name.rawValue)”",
            subtitle: "— \(panes)\(agents)", group: .workspaces, shortcut: nil, isCurrent: false)
    }

    /// F7: "Exportar layout “solen-dev”…", right after its restore.
    private static func exportCommand(_ layout: NamedLayoutSummary) -> Command {
        Command(
            id: .layoutExport(layout.name), title: "Exportar layout “\(layout.name.rawValue)”…", subtitle: nil,
            group: .workspaces, shortcut: nil, isCurrent: false)
    }

    fileprivate struct Context {
        let workspaces: WorkspaceSet
        let keymap: Keymap
        let integrations: [IntegrationID: IntegrationState]

        var paneCount: Int { workspaces.active.panes.count }

        func command(_ id: CommandID, _ title: String, subtitle: String? = nil, group: CommandGroup) -> Command {
            Command(
                id: id, title: title, subtitle: subtitle, group: group, shortcut: keymap.chord(for: id),
                isCurrent: false)
        }

        func titled(_ id: CommandID, group: CommandGroup) -> Command {
            command(id, CommandCatalog.titles[id] ?? id.rawValue, group: group)
        }
    }

    private static func tilingCommands(_ context: Context, _ layouts: LayoutCatalog) -> [Command] {
        var commands = layouts.all.map { layoutCommand($0, context) }
        if context.paneCount >= 2 {
            commands.append(
                Command(
                    id: .panesEqualize, title: "Igualar tamaños de paneles", subtitle: nil, group: .tiling,
                    shortcut: context.keymap.chord(for: .panesEqualize), isCurrent: false, icon: .equalize))
        }
        return commands
    }

    private static func layoutCommand(_ layout: any LayoutStrategy, _ context: Context) -> Command {
        let id = CommandID.layout(layout.id)
        return Command(
            id: id, title: "Layout: \(layout.displayName)", subtitle: layout.subtitle, group: .tiling,
            shortcut: context.keymap.chord(for: id), isCurrent: layout.id == context.workspaces.active.layout.id,
            icon: layout.icon)
    }

    private static func paneCommands(_ context: Context) -> [Command] {
        var commands = [context.command(.paneNew, "Nuevo panel", group: .panes)]
        if context.paneCount >= 1 {
            commands.append(context.command(.paneClose, "Cerrar panel", group: .panes))
            commands.append(context.command(.historySearch, "Buscar en el historial", group: .panes))
            commands.append(context.command(.editorOpenBeside, "Abrir Neovim junto al agente", group: .panes))
            commands.append(
                context.command(.editorOpenLastEdited, "Abrir en Neovim el último archivo editado", group: .panes))
        }
        commands += goToPaneCommands(context)
        if context.paneCount >= 2 {
            commands += directionalCommands(context)
        }
        return commands
    }

    /// Only numbered panes get one, as only they have a ⌘N shortcut.
    private static func goToPaneCommands(_ context: Context) -> [Command] {
        context.workspaces.active.panes.prefix(NumberedShortcuts.range.upperBound).enumerated().map { index, pane in
            let number = index + 1
            let process = pane.headerName
            return context.command(
                .paneFocus(number), "Ir al panel \(number)", subtitle: process.isEmpty ? nil : process,
                group: .panes)
        }
    }

    private static func directionalCommands(_ context: Context) -> [Command] {
        let actions: [(verb: String, id: (Direction) -> CommandID)] = [
            ("Enfocar", CommandID.paneFocus), ("Intercambiar", CommandID.paneSwap), ("Agrandar", CommandID.paneResize),
        ]
        return actions.flatMap { action in
            Direction.allCases.map { direction in
                context.command(
                    action.id(direction), "\(action.verb) panel hacia \(direction.spanishPhrase)", group: .panes)
            }
        }
    }

    private static func workspaceCommands(_ context: Context) -> [Command] {
        var commands = [
            context.command(.agentJump, "Saltar al agente que espera", group: .workspaces),
            context.command(.observatoryToggle, "Abrir observatorio", group: .workspaces),
            context.command(.observatoryFilter, "Filtrar el Observatorio", group: .workspaces),
            context.command(.harnessSearch, "Buscar sesiones de agentes", group: .workspaces),
            context.command(.workspaceNew, "Nuevo workspace", group: .workspaces),
            context.command(.workspaceRename, "Renombrar workspace…", group: .workspaces),
            context.titled(.layoutImport, group: .workspaces),
        ]
        let others = context.workspaces.workspaces.filter { $0.id != context.workspaces.activeID }
        commands += others.map {
            context.command(.workspaceGo($0.id), "Ir a workspace \($0.name)", group: .workspaces)
        }
        if context.workspaces.workspaces.count >= 2 {
            commands.append(context.command(.workspaceClose, "Cerrar workspace", group: .workspaces))
        }
        return commands
    }

    private static func configurationCommands(_ context: Context) -> [Command] {
        [
            context.command(
                .configReload, "Recargar configuración", subtitle: configPathSubtitle, group: .configuration)
        ] + integrationCommands(context) + [
            context.titled(.configOpen, group: .configuration),
            context.titled(.secureInputToggle, group: .configuration),
        ] + CommandID.appearance.map { context.titled($0, group: .configuration) }
    }
}

/// One action per integration, the one its state allows (spec F5.6, F6).
private func integrationCommands(_ context: CommandCatalog.Context) -> [Command] {
    IntegrationID.allCases.compactMap { integration in
        integration.commandID(for: context.integrations[integration, default: .unknown]).map {
            context.command($0.id, $0.title, group: .configuration)
        }
    }
}

/// What the catalog needs from the app besides the keymap and the layouts: the workspaces, the saved layouts and the
/// integrations' states (missing ones are unknown).
public struct CatalogState: Sendable {
    public let workspaces: WorkspaceSet
    public let savedLayouts: [NamedLayoutSummary]
    public let integrations: [IntegrationID: IntegrationState]
    /// F6: what the focused pane's Claude edited, newest first, and the time their age is told from.
    public let editedFiles: [EditedFile]
    public let now: Date
    /// F7.5: the commands waiting for approval in every window, oldest first.
    public var pendingApprovals: [ApprovalEntry] = []
    /// F7.5: the focused pane's project and whether its secrets are protected; nil without a pane.
    public var secretsProject: SecretsProjectState?

    public init(
        workspaces: WorkspaceSet, savedLayouts: [NamedLayoutSummary] = [],
        integrations: [IntegrationID: IntegrationState] = [:], editedFiles: [EditedFile] = [], now: Date = Date()
    ) {
        self.workspaces = workspaces
        self.savedLayouts = savedLayouts
        self.integrations = integrations
        self.editedFiles = editedFiles
        self.now = now
    }

    /// F7.5: the same state plus approvals and the secrets project.
    public init(
        workspaces: WorkspaceSet, integrations: [IntegrationID: IntegrationState] = [:],
        pendingApprovals: [ApprovalEntry] = [], secretsProject: SecretsProjectState? = nil
    ) {
        self.init(workspaces: workspaces, savedLayouts: [], integrations: integrations, editedFiles: [], now: Date())
        self.pendingApprovals = pendingApprovals
        self.secretsProject = secretsProject
    }
}

/// A waiting command and the workspace it waits in, as ⌘K lists it.
public struct ApprovalEntry: Equatable, Sendable {
    public let approval: PendingApproval
    public let workspace: String

    public init(approval: PendingApproval, workspace: String) {
        self.approval = approval
        self.workspace = workspace
    }
}

/// The focused pane's project for the secret rules: its folder name and whether Smalti's rules are in place.
public struct SecretsProjectState: Equatable, Sendable {
    public let name: String
    public let isProtected: Bool

    public init(name: String, isProtected: Bool) {
        self.name = name
        self.isProtected = isProtected
    }
}

extension Direction {
    /// The direction as it ends the sentence "… panel hacia …".
    fileprivate var spanishPhrase: String {
        switch self {
        case .left: "la izquierda"
        case .right: "la derecha"
        case .up: "arriba"
        case .down: "abajo"
        }
    }
}

/// A saved layout as the palette lists it.
public struct NamedLayoutSummary: Equatable, Sendable {
    public let name: LayoutName
    public let paneCount: Int
    public let agentCount: Int

    public init(name: LayoutName, paneCount: Int, agentCount: Int) {
        self.name = name
        self.paneCount = paneCount
        self.agentCount = agentCount
    }

    public init(name: LayoutName, layout: WorkspaceSnapshot) {
        self.init(name: name, paneCount: layout.panes.count, agentCount: layout.panes.count { $0.agent != nil })
    }
}
