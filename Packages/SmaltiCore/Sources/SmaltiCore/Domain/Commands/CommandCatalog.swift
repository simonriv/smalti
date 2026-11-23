/// Builds the commands the palette offers for the current state, in display order.
public enum CommandCatalog {
    private static let configPathSubtitle = "~/.config/smalti/config.toml"

    public static func commands(
        for set: WorkspaceSet, keymap: Keymap, layouts: LayoutCatalog, savedLayouts: [NamedLayoutSummary] = []
    ) -> [Command] {
        let context = Context(workspaces: set, keymap: keymap)
        return tilingCommands(context, layouts)
            + paneCommands(context)
            + workspaceCommands(context)
            + savedLayouts.map(restoreCommand)
            + configurationCommands(context)
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

    private struct Context {
        let workspaces: WorkspaceSet
        let keymap: Keymap

        var paneCount: Int { workspaces.active.panes.count }

        func command(_ id: CommandID, _ title: String, subtitle: String? = nil, group: CommandGroup) -> Command {
            Command(
                id: id, title: title, subtitle: subtitle, group: group, shortcut: keymap.chord(for: id),
                isCurrent: false)
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
            context.command(.workspaceNew, "Nuevo workspace", group: .workspaces),
            context.command(.workspaceRename, "Renombrar workspace…", group: .workspaces),
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
        ]
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
