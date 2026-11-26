import Foundation

/// Builds the commands the palette offers for the current state, in display order.
public enum CommandCatalog {
    private static let configPathSubtitle = "~/.config/smalti/config.toml"

    public static func commands(
        for state: CatalogState, keymap: Keymap, layouts: LayoutCatalog, texts: CommandTexts
    ) -> [Command] {
        let context = Context(
            workspaces: state.workspaces, keymap: keymap, integrations: state.integrations, updates: state.updates,
            texts: texts)
        return state.pendingApprovals.flatMap { approvalCommands($0, texts) }
            + projectCommands(state.projects, context)
            + tilingCommands(context, layouts)
            + paneCommands(context)
            + terminalCommands(context)
            + workspaceCommands(context)
            + (state.projects.flatMap { saveProjectCommand($0, context) }.map { [$0] } ?? [])
            + state.savedLayouts.flatMap { [restoreCommand($0, texts), exportCommand($0, texts)] }
            + windowCommands(context)
            + configurationCommands(context)
            + (state.secretsProject.map { [secretsCommand($0, texts)] } ?? [])
            + helpCommands(context)
            + state.editedFiles.map { editedFileCommand($0, now: state.now, texts: texts) }
    }

    /// F7.5: the longest part of a command an approval entry quotes.
    static let approvalQuoteLength = 40

    /// «Aprobar “terraform destroy” en rizaria» and its «Rechazar…», with the rule and the environment below.
    private static func approvalCommands(_ entry: ApprovalEntry, _ texts: CommandTexts) -> [Command] {
        let subject = entry.approval.subject
        let command = subject.command
        let quote =
            command.count > approvalQuoteLength ? String(command.prefix(approvalQuoteLength)) + "…" : command
        // Final review: a quoted command is cut, so the subtitle carries it whole (redacted).
        let whole = command.count > approvalQuoteLength ? command : nil
        let subtitle = [subject.summary(texts.guards), subject.environment.detail(texts.guards), whole].compactMap {
            $0
        }.joined(separator: " · ")
        return [
            (CommandID.guardApprove(id: entry.approval.id), texts.approve),
            (CommandID.guardReject(id: entry.approval.id), texts.reject),
        ].map { id, template in
            Command(
                id: id, title: template(["quote": quote, "workspace": entry.workspace]), subtitle: subtitle,
                group: .approvals, shortcut: nil, isCurrent: false)
        }
    }

    /// F7.5: «Proteger secretos en “rizaria”» or its undo, whichever applies.
    private static func secretsCommand(_ project: SecretsProjectState, _ texts: CommandTexts) -> Command {
        let (id, template) =
            project.isProtected
            ? (CommandID.secretsUnprotect, texts.unprotectSecrets) : (CommandID.secretsProtect, texts.protectSecrets)
        return Command(
            id: id, title: template(["name": project.name]), subtitle: nil, group: .configuration, shortcut: nil,
            isCurrent: false)
    }

    /// "reminder.service.ts", "línea 42 · hace 2 min".
    private static func editedFileCommand(_ file: EditedFile, now: Date, texts: CommandTexts) -> Command {
        let elapsed = ElapsedPhrase.text(since: file.at, now: now, texts: texts.time)
        return Command(
            id: .editorOpen(path: file.path, line: file.line), title: file.fileName,
            subtitle: texts.editedFileSubtitle(["line": String(file.line), "elapsed": elapsed]), group: .editedFiles,
            shortcut: nil, isCurrent: false)
    }

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
        [CommandID.helpShow, .helpWelcome, .helpDocs, .helpPrivacy, .feedbackReport, .logsShow].map {
            context.titled($0, group: .help)
        }
            + updateCommands(context)
            + [CommandID.appSupport, .appAbout].map { context.titled($0, group: .help) }
    }

    /// F7.6: only in a build that can update itself.
    private static func updateCommands(_ context: Context) -> [Command] {
        guard case .available(let isAutomatic) = context.updates else { return [] }
        let toggle = isAutomatic ? context.texts.turnOffAutomaticUpdates : context.texts.turnOnAutomaticUpdates
        return [context.titled(.updatesCheck, group: .help), context.command(.updatesAutomatic, toggle, group: .help)]
    }

    /// F8.5: «Abrir proyecto “rizaria” — ~/dev/rizaria · en este panel» for each project, then «Proyectos
    /// recientes…» (⌘O), which is always there.
    private static func projectCommands(_ projects: CatalogProjects?, _ context: Context) -> [Command] {
        let texts = context.texts
        let rows = (projects?.listings ?? []).map { listing in
            Command(
                id: .projectOpen(root: listing.root), title: texts.openProject(["name": listing.name]),
                subtitle: projectSubtitle(listing, home: projects?.home ?? "", texts: texts.projects),
                group: .projects, shortcut: nil, isCurrent: false, icon: .projectFolder)
        }
        let recent = context.command(
            .projectRecent, texts.titles[.projectRecent] ?? "", group: .projects, icon: .recentProjects)
        return rows + [recent]
    }

    private static func projectSubtitle(_ listing: ProjectListing, home: String, texts: ProjectTexts) -> String {
        let place: String? =
            if let open = listing.openIn {
                open.isInThisWindow
                    ? texts.openInWorkspace(["number": String(open.number)]) : texts.openInAnotherWindow
            } else if listing.isInFocusedPane {
                texts.inThisPane
            } else {
                nil
            }
        return ([ProjectPath.display(listing.root, home: home)] + [place].compactMap { $0 }).joined(separator: " · ")
    }

    /// F8.5: «Guardar layout del proyecto — escribe .smalti/layout.json en ~/dev/rizaria», with a pane to save.
    private static func saveProjectCommand(_ projects: CatalogProjects, _ context: Context) -> Command? {
        guard let root = projects.saveRoot else { return nil }
        let texts = context.texts
        return context.command(
            .projectSave, texts.titles[.projectSave] ?? "",
            subtitle: texts.saveProjectSubtitle(["root": ProjectPath.display(root, home: projects.home)]),
            group: .workspaces, icon: .saveProject)
    }

    /// "Guardar layout actual como “solen-dev”", offered for whatever the user typed when it is a valid name.
    public static func saveCommand(named query: String, texts: CommandTexts) -> Command? {
        guard let name = try? LayoutName(query) else { return nil }
        return Command(
            id: .layoutSave(name), title: texts.saveLayout(["name": name.rawValue]), subtitle: nil,
            group: .workspaces, shortcut: nil, isCurrent: false)
    }

    /// "Restaurar layout “rizaria-full” — 4 paneles, retoma 2 sesiones de Claude" (Paleta.dc.html).
    private static func restoreCommand(_ layout: NamedLayoutSummary, _ texts: CommandTexts) -> Command {
        let title = texts.restoreLayout(["name": layout.name.rawValue])
        if let format = layout.newerFormat {
            return Command(
                id: .layoutRestore(layout.name), title: title,
                subtitle: texts.restoreNewerFormat(["format": String(format)]), group: .workspaces, shortcut: nil,
                isCurrent: false)
        }
        let agents = layout.agentCount > 0 ? texts.restoreSessions(layout.agentCount) : ""
        return Command(
            id: .layoutRestore(layout.name), title: title, subtitle: texts.restorePanes(layout.paneCount) + agents,
            group: .workspaces, shortcut: nil, isCurrent: false)
    }

    /// F7: "Exportar layout “solen-dev”…", right after its restore.
    private static func exportCommand(_ layout: NamedLayoutSummary, _ texts: CommandTexts) -> Command {
        Command(
            id: .layoutExport(layout.name), title: texts.exportLayout(["name": layout.name.rawValue]), subtitle: nil,
            group: .workspaces, shortcut: nil, isCurrent: false)
    }

    fileprivate struct Context {
        let workspaces: WorkspaceSet
        let keymap: Keymap
        let integrations: [IntegrationID: IntegrationState]
        let updates: UpdatesAvailability
        let texts: CommandTexts

        var paneCount: Int { workspaces.active.panes.count }

        func command(
            _ id: CommandID, _ title: String, subtitle: String? = nil, group: CommandGroup, icon: CommandIcon? = nil
        ) -> Command {
            Command(
                id: id, title: title, subtitle: subtitle, group: group, shortcut: keymap.chord(for: id),
                isCurrent: false, icon: icon)
        }

        func titled(_ id: CommandID, group: CommandGroup) -> Command {
            command(id, texts.titles[id] ?? texts.paletteTitles[id] ?? id.rawValue, group: group)
        }
    }

    private static func tilingCommands(_ context: Context, _ layouts: LayoutCatalog) -> [Command] {
        var commands = layouts.all.map { layoutCommand($0, context) }
        if context.paneCount >= 2 {
            commands.append(
                Command(
                    id: .panesEqualize, title: context.texts.paletteTitles[.panesEqualize] ?? "", subtitle: nil,
                    group: .tiling,
                    shortcut: context.keymap.chord(for: .panesEqualize), isCurrent: false, icon: .equalize))
        }
        return commands
    }

    private static func layoutCommand(_ layout: any LayoutStrategy, _ context: Context) -> Command {
        let id = CommandID.layout(layout.id)
        return Command(
            id: id,
            title: context.texts.layoutTitle(["name": context.texts.layoutNames[layout.id] ?? layout.id.rawValue]),
            subtitle: context.texts.layoutSubtitles[layout.id], group: .tiling,
            shortcut: context.keymap.chord(for: id), isCurrent: layout.id == context.workspaces.active.layout.id,
            icon: layout.icon)
    }

    private static func paneCommands(_ context: Context) -> [Command] {
        var commands = [context.titled(.paneNew, group: .panes)]
        if context.paneCount >= 1 {
            commands += [CommandID.paneClose, .historySearch, .editorOpenBeside, .editorOpenLastEdited].map {
                context.titled($0, group: .panes)
            }
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
                .paneFocus(number), context.texts.goToPane(["number": String(number)]),
                subtitle: process.isEmpty ? nil : process,
                group: .panes)
        }
    }

    private static func directionalCommands(_ context: Context) -> [Command] {
        let texts = context.texts
        let actions: [(template: TextTemplate, id: (Direction) -> CommandID)] = [
            (texts.focusPane, CommandID.paneFocus), (texts.swapPane, CommandID.paneSwap),
            (texts.resizePane, CommandID.paneResize),
        ]
        return actions.flatMap { action in
            Direction.allCases.map { direction in
                let phrase = texts.directions[direction] ?? ""
                return context.command(action.id(direction), action.template(["direction": phrase]), group: .panes)
            }
        }
    }

    private static func workspaceCommands(_ context: Context) -> [Command] {
        var commands = [
            CommandID.agentJump, .observatoryToggle, .observatoryFilter, .harnessSearch,
        ].map { context.titled($0, group: .workspaces) }
        commands += CommandID.timeline.map { context.titled($0, group: .workspaces) }
        commands += CommandID.processes.map { context.titled($0, group: .workspaces) }
        commands += [CommandID.workspaceNew, .workspaceRename, .layoutImport].map {
            context.titled($0, group: .workspaces)
        }
        let others = context.workspaces.workspaces.filter { $0.id != context.workspaces.activeID }
        commands += others.map {
            context.command(
                .workspaceGo($0.id), context.texts.goToWorkspace(["name": $0.name]), group: .workspaces)
        }
        if context.workspaces.workspaces.count >= 2 {
            commands.append(context.titled(.workspaceClose, group: .workspaces))
        }
        return commands
    }

    private static func configurationCommands(_ context: Context) -> [Command] {
        [
            context.command(
                .configReload, context.texts.paletteTitles[.configReload] ?? "", subtitle: configPathSubtitle,
                group: .configuration)
        ] + integrationCommands(context) + [
            context.titled(.configOpen, group: .configuration),
            context.titled(.secureInputToggle, group: .configuration),
        ] + CommandID.appearance.map { context.titled($0, group: .configuration) }
    }
}

/// One action per integration, the one its state allows (spec F5.6, F6).
private func integrationCommands(_ context: CommandCatalog.Context) -> [Command] {
    IntegrationID.allCases.compactMap { integration in
        integration.command(
            for: context.integrations[integration, default: .unknown], texts: context.texts.integrations
        )
        .map { context.command($0.id, $0.title, group: .configuration) }
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
    /// F7.6: whether the build can update itself and checks on its own.
    public var updates = UpdatesAvailability.unavailable
    /// F8.5: the projects to offer and where "Guardar layout del proyecto" writes; `nil` lists none.
    public var projects: CatalogProjects?

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

/// A saved layout as the palette lists it.
public struct NamedLayoutSummary: Equatable, Sendable {
    public let name: LayoutName
    public let paneCount: Int
    public let agentCount: Int
    /// F7.6: set when a newer Smalti saved it; this build lists it but cannot open it.
    public let newerFormat: Int?

    public init(name: LayoutName, paneCount: Int, agentCount: Int) {
        self.name = name
        self.paneCount = paneCount
        self.agentCount = agentCount
        newerFormat = nil
    }

    public init(name: LayoutName, newerFormat: Int) {
        self.name = name
        paneCount = 0
        agentCount = 0
        self.newerFormat = newerFormat
    }

    public init(name: LayoutName, layout: WorkspaceSnapshot) {
        self.init(name: name, paneCount: layout.panes.count, agentCount: layout.panes.count { $0.agent != nil })
    }
}

/// F8.5: what ⌘K lists about projects: the listings, the home to write paths with `~`, and the repo the active
/// workspace would be saved to (`nil` without a pane).
public struct CatalogProjects: Equatable, Sendable {
    public let listings: [ProjectListing]
    public let home: String
    public let saveRoot: String?

    public init(listings: [ProjectListing], home: String, saveRoot: String?) {
        self.listings = listings
        self.home = home
        self.saveRoot = saveRoot
    }
}
