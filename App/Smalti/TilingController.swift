import Foundation
import OSLog
import SmaltiCore

/// The engine as the app needs it: the domain port plus the view of each pane.
typealias PaneEngine = TerminalEngine & TerminalViewProvider

/// What the views draw after every change.
extension TilingController.Dependencies {
    /// The same dependencies with this window's agents (F4.5: what counts as visible is per window).
    func with(agents: TilingController.AgentDependencies) -> TilingController.Dependencies {
        TilingController.Dependencies(
            engine: engine, configStore: configStore, paneEnvironment: paneEnvironment, transcripts: transcripts,
            namedLayouts: namedLayouts, harnesses: harnesses, captures: captures, editor: editor, updates: updates,
            agents: agents,
            home: home, shellOverride: shellOverride, applyAppearance: applyAppearance)
    }
}

struct TilingState {
    let set: WorkspaceSet
    let config: SmaltiConfig
    let theme: Theme
    /// F5: how opaque "Proteger legibilidad" made each surface; `chrome` backs the strip and the status bar.
    let opacities: SurfaceOpacities
    /// F5 "Solo símbolo": the prompt's context of the active workspace's panes, shown in their headers.
    var promptHeaders: [PaneID: String] = [:]
    let message: StatusMessage?
    /// Directories show relative to it (`~/dev/xolken`).
    let home: WorkingDirectory
    /// The observatory's latest refresh (F3): status-bar figures and the agents' model and context.
    var observatory: ObservatoryFrame?
    /// F4.5: secure keyboard entry is on (the menu or a password prompt).
    var isSecureInput = false
    /// F4.5: the link under the pointer while ⌘ is held.
    var hoveredLink: String?
    /// F7.5: the commands waiting for approval in each pane of the active workspace.
    var approvals: [PaneID: [PendingApproval]] = [:]
}

extension TilingState {
    /// F5: the glass-colored layer behind the strip and the status bar; clear when protection does not need it.
    var chromeBackground: RGBAColor { theme.window.background.withAlpha(opacities.chrome) }
}

/// Primary adapter between AppKit and the use cases: turns a `CommandID` (from a shortcut, the palette or a click)
/// and every terminal event into one use case call, then publishes the new state. It holds no tiling rules.
@MainActor
final class TilingController {
    struct Dependencies {
        let engine: any PaneEngine
        let configStore: any ConfigStore
        let paneEnvironment: PaneEnvironment
        let transcripts: any PaneTranscripts
        let namedLayouts: any NamedLayouts
        let harnesses: HarnessRegistry
        /// F6: captures the session of every harness pane, shared by all windows.
        let captures: HarnessCaptures
        /// F6: Neovim panes: the command they run, where their sockets go, and the edits shared by all windows.
        let editor: EditorSettings
        /// F7.6: nil in a build that cannot update itself (Smalti Dev without a test feed).
        let updates: (any AppUpdates)?
        let agents: AgentDependencies
        let home: WorkingDirectory
        let shellOverride: TerminalCommand?
        /// Reloads the terminal engine's appearance ("Recargar configuración").
        let applyAppearance: (TerminalAppearance) throws(TerminalEngineError) -> Void
    }

    /// What agent events need from outside the tiling.
    struct AgentDependencies {
        let notifier: any Notifier
        /// F5.6/F6: each integration's last known state, shared by every window.
        let integrations: [IntegrationID: ClaudeIntegrationStatus]
        let isAppActive: () -> Bool
        /// F7.5: the app's approvals; nil only before the composition root sets them.
        var guards: GuardDependencies?
    }

    /// F7.5: the app's approval queue, what ⌘K lists from every window, and the hook that drops approvals of panes
    /// that are gone.
    struct GuardDependencies {
        let approvals: AgentApprovals
        let entries: () -> [ApprovalEntry]
        let panesChanged: () -> Void
        /// ⌘K's secret rules, and the project a pane's folder belongs to.
        let secrets: ProtectProjectSecrets
        let projectRoot: (String) -> String
    }

    var onChange: ((TilingState) -> Void)?
    /// A new observatory snapshot: only the status bar and the headers repaint, nothing is saved.
    var onObservatoryChange: ((TilingState) -> Void)?
    private(set) var observatory: ObservatoryFrame?
    /// Supplies the pane area of the grid; the views own geometry.
    var area: () -> Rect = { .zero }
    /// Commands that open UI instead of changing tiling (the palette, the rename prompt) go to the views.
    var onViewCommand: ((CommandID) -> Void)?
    /// F4.5: commands about the app's windows (⌘N, ⇧⌘W, ⌘J across windows…) go to the app.
    var onAppCommand: ((CommandID) -> Void)?
    /// F4.5: terminal events only the views use (search progress, link hover, secure input), with their pane.
    var onViewEvent: ((TerminalEvent, PaneID) -> Void)?
    /// F4.5: asks the user before closing a running program; `proceed` runs only if they confirm.
    var onConfirmClose: ((CloseQuestion, _ proceed: @escaping () -> Void) -> Void)?

    /// What `onAppCommand` receives: they act on several windows or on the window itself.
    static let appCommands: Set<CommandID> = [
        .windowNew, .windowClose, .windowFullscreen, .windowMinimize, .agentJump, .configReload, .appAbout,
        .configOpen, .secureInputToggle, .feedbackReport, .logsShow, .fontIncrease, .fontDecrease, .fontReset,
        .appearanceOpen, .themeOpen, .themeNext, .ansiReset, .legibilityToggle, .promptStudio, .promptApply,
        .promptExport, .layoutImport, .updatesCheck, .updatesAutomatic, .helpDocs, .appSupport, .helpWelcome,
        .helpPrivacy,
    ]

    private let deps: Dependencies
    private let layouts = LayoutCatalog.standard
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "tiling")
    private(set) var set: WorkspaceSet
    private(set) var config: SmaltiConfig {
        didSet { applied = ThemeCatalog.apply(config.appearance) }
    }
    /// F5: the theme of `config.appearance`, protected; computed once per config, not per access.
    private(set) var applied: AppliedTheme
    private var status = StatusSlot<StatusMessage>()
    private var messageClearing: Task<Void, Never>?
    private var openedAt: [PaneID: ContinuousClock.Instant] = [:]
    /// `restore` signpost: ends when every restored pane's shell showed its first prompt (it is interactive).
    private let signposter = OSSignposter(subsystem: AppIdentity.current.bundleIdentifier, category: "restore")
    private var pendingRestore: (interval: OSSignpostIntervalState, panes: Set<PaneID>)?
    private var minuteTicker: Task<Void, Never>?
    /// F6: this window's Neovim panes.
    private(set) lazy var editors: EditorCoordinator = {
        let coordinator = EditorCoordinator(settings: deps.editor, home: deps.home.path)
        coordinator.host = self
        return coordinator
    }()

    /// `initial` is the startup load, done before the engine exists because the engine needs its appearance.
    init(_ deps: Dependencies, initial reload: ConfigReload) {
        self.deps = deps
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        applied = ThemeCatalog.apply(reload.config.appearance)
        let layout = LayoutCatalog.standard.strategyOrDefault(for: config.defaultLayout)
        set = WorkspaceSet(first: .empty(name: deps.home.lastComponent, rootDirectory: deps.home, layout: layout))
        status = status.withPersistent(reload.error.map(StatusMessage.invalidConfig))
    }

    var theme: Theme { applied.theme }

    var home: WorkingDirectory { deps.home }

    var geometry: LayoutGeometry {
        LayoutGeometry(area: area(), gap: theme.panel.gap, minimumPaneSize: LayoutGeometry.standardMinimumPaneSize)
    }

    /// Opens the first pane of the first workspace.
    func start() {
        openPane()
        publish()
    }

    /// F4.5 ⌘N: a new window starts with one workspace rooted at `directory` (the focused pane's of the window it came
    /// from) and its first pane.
    func start(in directory: WorkingDirectory) {
        let layout = layouts.strategyOrDefault(for: config.defaultLayout)
        set = WorkspaceSet(first: .empty(name: directory.lastComponent, rootDirectory: directory, layout: layout))
        start()
    }

    /// An agent's hook event, from the IPC socket.
    func handle(_ event: AgentEvent) {
        if event.edit != nil {
            let edited = deps.editor.editedFiles
            Task { await edited.record(event) }
        }
        _ = HandleAgentEvent(notifier: deps.agents.notifier, texts: .current).execute(
            event, in: &set, isAppActive: deps.agents.isAppActive())
        publish()
    }

    /// A click on a notification: show its pane (switching workspace); if it is gone, only the app comes forward.
    /// False when the pane no longer exists.
    @discardableResult
    func activate(_ pane: PaneID) -> Bool {
        guard ActivatePane(engine: deps.engine).execute(pane, in: &set) else { return false }
        publish()
        return true
    }

    // MARK: - Approvals (F7.5)

    /// ⌘⇧↩ / ⌘⇧⎋: the oldest command waiting in the focused pane.
    private func decideOldest(approve: Bool) {
        guard let approvals = deps.agents.guards?.approvals, let pane = set.active.focusedPane else { return }
        let now = Date()
        let outcome = approve ? approvals.approveOldest(in: pane, now: now) : approvals.rejectOldest(in: pane, now: now)
        switch outcome {
        case .decided: show(approve ? .commandApproved : .commandRejected)
        case .nothingWaiting: show(.noApprovalWaiting)
        // Final review: the card has just changed to a command the user has not read; the press is ignored.
        case .tooSoon: break
        }
    }

    /// ⌘K: one waiting command, wherever it is.
    private func decide(_ command: ApprovalCommand) {
        guard let approvals = deps.agents.guards?.approvals else { return }
        switch command {
        case .approve(let id): show(approvals.approve(id) ? .commandApproved : .approvalGone)
        case .reject(let id): show(approvals.reject(id) ? .commandRejected : .approvalGone)
        }
    }

    /// The focused pane's project for the secret rules; nil without a pane.
    private var secretsProject: String? {
        guard let guards = deps.agents.guards, let pane = set.active.focusedPane,
            let directory = set.active.panes.first(where: { $0.id == pane })?.workingDirectory.path
        else { return nil }
        return guards.projectRoot(directory)
    }

    private func secretsProjectState() -> SecretsProjectState? {
        guard let guards = deps.agents.guards, let project = secretsProject, guards.secrets.canProtect(project) else {
            return nil
        }
        // An unreadable settings file offers protecting, which then says why it cannot.
        let isProtected = (try? guards.secrets.isProtected(project)) ?? false
        return SecretsProjectState(name: URL(filePath: project).lastPathComponent, isProtected: isProtected)
    }

    private func changeSecretRules(protect: Bool) {
        guard let guards = deps.agents.guards, let project = secretsProject else { return }
        let name = URL(filePath: project).lastPathComponent
        do {
            if protect { try guards.secrets.protect(project) } else { try guards.secrets.unprotect(project) }
            show(protect ? .secretsProtected(name) : .secretsUnprotected(name))
        } catch {
            show(.secretsFailed(error.message(.current)))
        }
    }

    /// An approval changed somewhere: the window that has the pane shows it.
    func handleApproval(_ change: AgentApprovalChange) {
        if case .blocked(let pane, let path) = change {
            guard set.workspace(containing: pane) != nil else { return }
            show(.secretBlocked(path))
        } else {
            HandleApprovalChange(notifier: deps.agents.notifier, texts: .current).execute(change, in: &set)
        }
        publish()
    }

    func reportNobodyWaiting() {
        show(.nobodyWaiting)
    }

    private func runIntegration(_ id: IntegrationID, _ command: IntegrationCommand.Type) {
        guard let status = deps.agents.integrations[id] else { return }
        let integration = status.integration
        status.changeStarted()
        Task { [weak self] in
            let line = await command.init(integration: integration, id: id, texts: .current).execute()
            self?.report(.integration(line))
            status.refresh(forced: true)
        }
    }

    /// What ⌘K lists besides the keymap: the workspaces, the saved layouts and the Claude integration's state.
    func catalogState() -> CatalogState {
        var state = CatalogState(
            workspaces: set, savedLayouts: savedLayouts(),
            integrations: deps.agents.integrations.mapValues(\.state),
            editedFiles: set.active.focusedPane.map {
                deps.editor.editedFiles.recent(in: $0, workspace: set.active.panes.map(\.id))
            } ?? [])
        state.pendingApprovals = deps.agents.guards?.entries() ?? []
        state.secretsProject = secretsProjectState()
        state.updates = UpdatesAvailability(deps.updates)
        return state
    }

    /// Asks again whether the Claude integration is installed; ⌘K calls it each time it opens.
    func refreshIntegrationState() {
        deps.agents.integrations.values.forEach { $0.refresh(forced: false) }
    }

    /// The saved layouts as the palette lists them.
    func savedLayouts() -> [NamedLayoutSummary] {
        ListNamedLayouts(layouts: deps.namedLayouts).execute()
    }

    private func perform(_ command: NamedLayoutCommand) {
        switch command {
        case .save(let name):
            do {
                try SaveNamedLayout(layouts: deps.namedLayouts).execute(set.active, as: name)
                show(.layoutSaved(name.rawValue))
            } catch {
                show(.layoutSaveFailed(name.rawValue, reason: error.summary(.current)))
            }
        case .restore(let name): restoreLayout(name)
        // F7: the save panel belongs to the window, so the app runs it.
        case .export(let name): onAppCommand?(.layoutExport(name))
        }
    }

    private func restoreLayout(_ name: LayoutName) {
        do {
            let outcome = try RestoreNamedLayout(layouts: deps.namedLayouts, restore: restoreSession).execute(
                name, into: &set, home: deps.home)
            set.active.panes.forEach { observe($0.id) }
            if let skipped = outcome.skippedLiveSessions.first { show(.sessionAlreadyOpen(skipped)) }
            reportRestoreFailures(outcome.failures)
        } catch {
            show(.layoutRestoreFailed(name.rawValue, reason: error.summary(.current)))
        }
    }

    private var restoreSession: RestoreSession {
        let nvim = deps.editor.nvim
        let socketDirectory = deps.editor.socketDirectory
        return RestoreSession(
            .init(
                engine: deps.engine, transcripts: deps.transcripts, harnesses: deps.harnesses,
                environment: deps.paneEnvironment, shell: config.shell, clock: { .now }, texts: .current,
                // F6: Claude reopens with `--ide` while claudecode.nvim is installed.
                connectsEditor: deps.editor.connectsEditor(),
                editorCommand: { position, pane in
                    EditorCommand.reopen(nvim: nvim, socketDirectory: socketDirectory, position: position, pane: pane)
                }))
    }

    /// Rebuilds one saved window's workspaces; if none could open, starts as usual.
    func restore(_ plan: RestorePlan, savedAt: Date) {
        let interval = signposter.beginInterval("restore", id: signposter.makeSignpostID())
        let result = restoreSession.execute(plan, savedAt: savedAt, home: deps.home)
        guard let restored = result.set else {
            signposter.endInterval("restore", interval)
            start()
            reportRestoreFailures(result.failures)
            return
        }
        set = restored
        adoptRestoredEditors(plan)
        pendingRestore = (interval, Set(set.workspaces.flatMap(\.panes).map(\.id)))
        set.workspaces.flatMap(\.panes).forEach { observe($0.id) }
        reportRestoreFailures(result.failures)
        publish()
    }

    /// F6: the Neovim panes reopened with `--listen` answer "Abrir en Neovim" and are saved at their line again.
    private func adoptRestoredEditors(_ plan: RestorePlan) {
        for planned in plan.workspaces.flatMap(\.panes) {
            guard let socket = restoredSocket(planned) else { continue }
            editors.adopt(PaneID(rawValue: planned.id), socket: socket)
        }
    }

    /// An editor pane's socket, or the one a Neovim saved as its process listened on (final review).
    private func restoredSocket(_ planned: PlannedPane) -> String? {
        let directory = deps.editor.socketDirectory
        switch planned.launch {
        case .editor: return try? EditorSocketPath.make(directory: directory, pane: PaneID(rawValue: planned.id))
        case .relaunch(let command): return EditorCommand.listenSocket(in: command.arguments, directory: directory)
        case .shell, .resume: return nil
        }
    }

    func perform(_ command: CommandID) {
        if Self.appCommands.contains(command) {
            onAppCommand?(command)
            return
        }
        if Self.viewCommands.contains(command) {
            onViewCommand?(command)
            return
        }
        guard let action = action(for: command) else {
            // A `CommandID` names an action, never typed text; bound to its own name for the log guard (F4.5).
            let commandID = command.rawValue
            logger.error("unknown command \(commandID, privacy: .public)")
            return
        }
        action()
        publish()
    }

    func focus(_ pane: PaneID) {
        guard let index = set.active.index(of: pane) else { return }
        FocusPane().execute(.index(index), geometry: geometry, in: &set)
        publish()
    }

    /// A message from outside the tiling use cases (e.g. a failed session save).
    func report(_ message: StatusMessage) {
        show(message)
        publish()
    }

    func rename(to name: String) {
        RenameWorkspace().execute(name, in: &set)
        publish()
    }

    // MARK: - Commands

    private static let viewCommands: Set<CommandID> = [
        .paletteOpen, .workspaceRename, .observatoryToggle, .observatoryPeriod, .historySearch, .helpShow,
        .searchOpen, .searchNext, .searchPrevious, .previewQuickLook, .harnessSearch, .observatoryFilter,
    ]

    private func action(for command: CommandID) -> (() -> Void)? {
        if let action = fixedActions[command] { return action }
        if let target = command.editorTarget {
            return { [unowned self] in
                if let pane = set.active.focusedPane { editors.open(target, from: pane) }
            }
        }
        if let named = command.namedLayout { return { [unowned self] in perform(named) } }
        if let approval = command.approval { return { [unowned self] in decide(approval) } }
        if let action = layoutActions[command] { return action }
        return workspaceGoAction(command)
    }

    /// Built once: the closures read the controller's state when they run, not when they are built.
    /// `unowned` is safe because the controller owns them.
    private lazy var fixedActions: [CommandID: () -> Void] = {
        var actions: [CommandID: () -> Void] = [
            .paneNew: { [unowned self] in openPane() },
            .editorOpenBeside: { [unowned self] in
                if let pane = set.active.focusedPane { editors.openBeside(pane) }
            },
            .editorOpenLastEdited: { [unowned self] in
                if let pane = set.active.focusedPane { editors.openLastEdited(from: pane) }
            },
            .paneClose: { [unowned self] in closeFocusedPane() },
            .panesEqualize: { [unowned self] in EqualizePanes().execute(in: &set) },
            .workspaceNew: { [unowned self] in createWorkspace() },
            .workspaceClose: { [unowned self] in closeActiveWorkspace() },
            .claudeIntegrationInstall: { [unowned self] in runIntegration(.claudePlugin, InstallClaudeIntegration.self)
            },
            .claudeIntegrationUninstall: { [unowned self] in
                runIntegration(.claudePlugin, UninstallClaudeIntegration.self)
            },
            .claudecodeNvimInstall: { [unowned self] in runIntegration(.claudecodeNvim, InstallClaudeIntegration.self)
            },
            .claudecodeNvimUninstall: { [unowned self] in
                runIntegration(.claudecodeNvim, UninstallClaudeIntegration.self)
            },
            .guardApprove: { [unowned self] in decideOldest(approve: true) },
            .guardReject: { [unowned self] in decideOldest(approve: false) },
            .secretsProtect: { [unowned self] in changeSecretRules(protect: true) },
            .secretsUnprotect: { [unowned self] in changeSecretRules(protect: false) },
            .terminalCopy: { [unowned self] in performInFocusedPane(.copy) },
            .terminalPaste: { [unowned self] in performInFocusedPane(.paste) },
            .terminalSelectAll: { [unowned self] in performInFocusedPane(.selectAll) },
            .terminalClear: { [unowned self] in performInFocusedPane(.clear) },
            .scrollPageUp: { [unowned self] in performInFocusedPane(.scroll(.pageUp)) },
            .scrollPageDown: { [unowned self] in performInFocusedPane(.scroll(.pageDown)) },
            .scrollTop: { [unowned self] in performInFocusedPane(.scroll(.top)) },
            .scrollBottom: { [unowned self] in performInFocusedPane(.scroll(.bottom)) },
            .promptPrevious: { [unowned self] in performInFocusedPane(.jumpToPrompt(.previous)) },
            .promptNext: { [unowned self] in performInFocusedPane(.jumpToPrompt(.next)) },
        ]
        for number in NumberedShortcuts.range {
            actions[.paneFocus(number)] = { [unowned self] in
                FocusPane().execute(.index(number), geometry: geometry, in: &set)
            }
            actions[.workspace(number)] = { [unowned self] in
                SwitchWorkspace(engine: deps.engine).execute(.index(number), in: &set)
            }
        }
        for direction in Direction.allCases { actions.merge(directionActions(direction)) { $1 } }
        return actions
    }()

    /// F4.5: ⌘C, ⌘V and ⌘A are Smalti commands now; the engine runs them in the focused pane.
    private func performInFocusedPane(_ action: TerminalAction) {
        guard let pane = set.active.focusedPane else { return }
        deps.engine.perform(action, in: pane)
    }

    private func directionActions(_ direction: Direction) -> [CommandID: () -> Void] {
        [
            .paneFocus(direction): { [unowned self] in
                FocusPane().execute(.direction(direction), geometry: geometry, in: &set)
            },
            .paneSwap(direction): { [unowned self] in
                SwapPane().execute(toward: direction, geometry: geometry, in: &set)
            },
            .paneResize(direction): { [unowned self] in
                ResizePane().execute(toward: direction, geometry: geometry, in: &set)
            },
        ]
    }

    /// One action per registered layout, so a new layout type needs no change here (OCP).
    private var layoutActions: [CommandID: () -> Void] {
        Dictionary(
            uniqueKeysWithValues: layouts.all.map { layout in
                (CommandID.layout(layout.id), { [unowned self] in SwitchLayout().execute(to: layout, in: &set) })
            })
    }

    private func workspaceGoAction(_ command: CommandID) -> (() -> Void)? {
        guard let target = set.workspaces.first(where: { CommandID.workspaceGo($0.id) == command }) else { return nil }
        return { [unowned self] in SwitchWorkspace(engine: deps.engine).execute(.id(target.id), in: &set) }
    }

    // MARK: - Use cases with outcomes

    private func openPane() {
        let request = OpenPaneRequest(shell: config.shell, geometry: geometry, home: deps.home)
        do {
            let pane = try OpenPane(engine: deps.engine, environment: deps.paneEnvironment).execute(request, in: &set)
            observe(pane)
        } catch {
            show(Self.message(for: error))
        }
    }

    /// F6: a saved session opened from the search, in a new pane of the active workspace.
    func openHarnessSession(_ plan: OpenPlan, directory: String?) {
        switch plan {
        case .open(let command, let path, let folderMissing, let binding):
            let request = OpenPaneRequest(
                shell: config.shell, geometry: geometry, home: deps.home,
                directory: path.flatMap { try? WorkingDirectory(path: $0) } ?? deps.home,
                initialInput: command + "\n", binding: binding)
            do {
                let pane = try OpenPane(engine: deps.engine, environment: deps.paneEnvironment).execute(
                    request, in: &set)
                observe(pane)
                if folderMissing {
                    show(
                        .harnessSession(
                            OpenHarnessSession.folderMissingMessage(directory ?? "", texts: .current)))
                }
            } catch {
                show(Self.message(for: error))
            }
            publish()
        case .cannotFork(let harness):
            show(.harnessSession(OpenHarnessSession.cannotForkMessage(harness, texts: .current)))
        case .unavailable(let harness):
            show(.harnessSession(OpenHarnessSession.unavailableMessage(harness, texts: .current)))
        }
    }

    private func createWorkspace() {
        let layout = layouts.strategyOrDefault(for: config.defaultLayout)
        let request = CreateWorkspaceRequest(
            pane: OpenPaneRequest(shell: config.shell, geometry: geometry, home: deps.home), layout: layout)
        do {
            _ = try CreateWorkspace(engine: deps.engine, environment: deps.paneEnvironment).execute(request, in: &set)
            set.active.panes.forEach { observe($0.id) }
        } catch {
            show(Self.message(for: error))
        }
    }

    private func closeFocusedPane() {
        guard let pane = set.active.focusedPane else { return }
        let panes = set.active.panes.filter { $0.id == pane }
        confirmClosing(.pane, panes) { [weak self] in self?.close(pane) }
    }

    /// Closes at once when nothing runs (or `confirm_close` is off); otherwise only after the user confirms, and
    /// then publishes itself, since the question returns after `perform` did.
    private func confirmClosing(_ scope: CloseScope, _ panes: [Pane], close: @escaping () -> Void) {
        let busy = RunningPrograms(engine: deps.engine, texts: .current).busy(in: panes)
        guard
            let question = CloseGuard.question(
                for: scope, busy: busy, settings: config.window, texts: .current),
            let onConfirmClose
        else {
            close()
            return
        }
        onConfirmClose(question) { [weak self] in
            close()
            self?.publish()
        }
    }

    private func close(_ pane: PaneID) {
        _ = ClosePane(engine: deps.engine).execute(pane, in: &set)
        forget([pane])
    }

    /// Every way a pane goes (⌘W, its shell exiting, its workspace or window closing) drops what was kept for it:
    /// its claim on a harness session, its Neovim socket and Claude's edits.
    private func forget(_ panes: [PaneID]) {
        for pane in panes {
            openedAt[pane] = nil
            deps.captures.forget(pane)
            editors.forget(pane)
        }
    }

    /// F6: the window is closing; its panes are gone with it.
    func forgetAllPanes() {
        forget(set.workspaces.flatMap(\.panes).map(\.id))
    }

    /// The only workspace cannot close; a shortcut bound in config.toml can still ask, and the refusal leaves
    /// everything as it was (the palette does not offer the command then).
    private func closeActiveWorkspace() {
        let workspace = set.active
        guard set.workspaces.count > 1 else {
            logger.debug("refused to close the last workspace")
            return
        }
        confirmClosing(.workspace(name: workspace.name), workspace.panes) { [weak self] in
            self?.closeWorkspace(workspace.id)
        }
    }

    private func closeWorkspace(_ id: WorkspaceID) {
        do {
            forget(try CloseWorkspace(engine: deps.engine).execute(id, in: &set))
        } catch {
            switch error {
            case .cannotCloseLastWorkspace: logger.debug("refused to close the last workspace")
            }
        }
    }

    /// "Recargar configuración" in the window that also reloads the terminal engine (it is the app's).
    @discardableResult
    func reloadConfig() -> Bool {
        guard applyReloadedConfig() else {
            publish()
            return false
        }
        do {
            try deps.applyAppearance(engineAppearance)
        } catch {
            show(.engineFailure(error))
        }
        publish()
        return true
    }

    /// F5 Apariencia: the panel's document, painted at once in this window (keys, shell and the rest stay).
    func adopt(_ document: AppearanceDocument) {
        config = document.applied(to: config)
        publish()
    }

    /// The theme's terminal with the config's `[keyboard] option_as_meta` (F7.7).
    private var engineAppearance: TerminalAppearance {
        var appearance = theme.terminal
        appearance.optionAsMeta = config.optionAsMeta
        return appearance
    }

    /// The engine's appearance is the app's: one window gives it the theme's terminal colors and font.
    func applyEngineAppearance() {
        do {
            try deps.applyAppearance(engineAppearance)
        } catch {
            show(.engineFailure(error))
        }
    }

    /// "Recargar configuración" in the other windows: they read the file again; the engine is already reloaded.
    @discardableResult
    func rereadConfig() -> Bool {
        let isReloaded = applyReloadedConfig()
        publish()
        return isReloaded
    }

    /// Reads the file; false when it was invalid (the status bar says so and the last good config stays).
    private func applyReloadedConfig() -> Bool {
        let reload = ReloadConfig(store: deps.configStore).execute()
        // Block 4 review (C1): a file that does not load keeps what is painted now (Apariencia's edits included),
        // not the last config the store read.
        if let error = reload.error {
            show(.invalidConfig(error))
            return false
        }
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        status = status.withPersistent(nil)
        // F5: keys repeated in config.toml and theme.toml ("theme.toml manda sobre config.toml en: …").
        if let warning = reload.warnings.first { show(.configWarning(warning.message(.current))) }
        return true
    }

    private static func message(for error: OpenPaneError) -> StatusMessage {
        switch error {
        case .paneTooSmall(let minimum): .paneTooSmall(minimum: minimum)
        case .engine(let engineError): .engineFailure(engineError)
        }
    }

    // MARK: - Terminal events

    private func observe(_ pane: PaneID) {
        guard openedAt[pane] == nil else { return }
        openedAt[pane] = .now
        let events = deps.engine.events(for: pane)
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event, from: pane)
            }
        }
    }

    private func handle(_ event: TerminalEvent, from pane: PaneID) {
        if Self.showsAPrompt(event) { restoredPaneIsInteractive(pane) }
        switch event {
        case .exited(let code): paneExited(pane, code: code)
        case .closeRequested: close(pane)
        case .searchTotal, .searchSelected, .linkHovered, .secureInputRequested, .pointerWordChanged:
            onViewEvent?(event, pane)
            return
        default:
            guard let owner = set.workspace(containing: pane) else { return }
            set = set.updating(owner) { $0.applying(event, to: pane, at: .now) }
            if case .foregroundProcessChanged(let process) = event { captureHarness(in: pane, running: process) }
        }
        publish()
    }

    /// F6: a harness that starts in a pane gets its session captured; the binding lands on the pane later.
    private func captureHarness(in id: PaneID, running process: ForegroundProcess) {
        guard let current = pane(id) else { return }
        deps.captures.processChanged(
            in: current, to: process,
            currentPane: { [weak self] in self?.pane(id) },
            apply: { [weak self] binding in
                guard let self, let owner = set.workspace(containing: id) else { return }
                set = set.updating(owner) { $0.binding(binding, to: id) }
                publish()
            })
    }

    private func pane(_ id: PaneID) -> Pane? {
        set.workspaces.lazy.flatMap(\.panes).first { $0.id == id }
    }

    /// The shell integration reports title and directory at every prompt: the first one means the pane is ready.
    private static func showsAPrompt(_ event: TerminalEvent) -> Bool {
        switch event {
        case .titleChanged, .workingDirectoryChanged: true
        default: false
        }
    }

    private func reportRestoreFailures(_ failures: [String]) {
        guard let first = failures.first else { return }
        report(.restoreFailures(first: first, count: failures.count))
    }

    private func restoredPaneIsInteractive(_ pane: PaneID) {
        guard var pending = pendingRestore, pending.panes.remove(pane) != nil else { return }
        if pending.panes.isEmpty {
            signposter.endInterval("restore", pending.interval)
            pendingRestore = nil
        } else {
            pendingRestore = pending
        }
    }

    private func paneExited(_ pane: PaneID, code: Int?) {
        // A pane that ends before reporting its directory no longer holds the restore signpost open.
        restoredPaneIsInteractive(pane)
        let lifetime = openedAt[pane].map { ContinuousClock.now - $0 } ?? .zero
        openedAt[pane] = nil
        let outcome = HandlePaneExit(engine: deps.engine).execute(
            PaneExit(pane: pane, exitCode: code, lifetime: lifetime), in: &set)
        if case .closedAfterFailedStart(let exitCode) = outcome { show(.failedStart(exitCode: exitCode)) }
        if self.pane(pane) == nil { forget([pane]) }
    }

    // MARK: - Publishing

    /// A transient message shows over a persistent one and then gives the line back (`StatusSlot`).
    private func show(_ newMessage: StatusMessage) {
        guard newMessage.isTransient else {
            status = status.withPersistent(newMessage)
            return
        }
        status = status.withTransient(newMessage)
        messageClearing?.cancel()
        messageClearing = Task { [weak self] in
            try? await Task.sleep(for: StatusMessage.transientDuration)
            guard !Task.isCancelled, let self else { return }
            self.status = self.status.clearingTransient(newMessage)
            self.publish()
        }
    }

    private func publish() {
        editors.noteFocus(set.active.focusedPane)
        deps.agents.guards?.panesChanged()
        onChange?(state)
        keepMinutesFresh()
    }

    /// F5 "Solo símbolo": each pane's prompt context, from the app's `RenderPrompt`.
    var promptHeader: ((PaneID) -> String?)?

    /// Something the views show changed outside this controller (a pane's prompt context).
    func refresh() { publish() }

    private var state: TilingState {
        var state = TilingState(
            set: set, config: config, theme: theme, opacities: applied.opacities, message: status.showing,
            home: deps.home, observatory: observatory,
            isSecureInput: isSecureInput, hoveredLink: hoveredLink)
        if let promptHeader {
            for pane in set.active.panes { state.promptHeaders[pane.id] = promptHeader(pane.id) }
        }
        if let approvals = deps.agents.guards?.approvals {
            for pane in set.active.panes { state.approvals[pane.id] = approvals.pending(in: pane.id) }
        }
        return state
    }

    private var isSecureInput = false
    private var hoveredLink: String?

    /// F4.5: the status bar says "Entrada segura" while it is on; nothing is saved for it.
    func showSecureInput(_ isOn: Bool) {
        guard isOn != isSecureInput else { return }
        isSecureInput = isOn
        onObservatoryChange?(state)
    }

    /// F4.5: the link under the pointer, in the status bar while ⌘ is held over it.
    func showHoveredLink(_ url: String?) {
        guard url != hoveredLink else { return }
        hoveredLink = url
        onObservatoryChange?(state)
    }

    func show(_ frame: ObservatoryFrame) {
        observatory = frame
        onObservatoryChange?(state)
    }

    /// "te espera · 2m" and a working agent's lifetime count minutes: while any agent runs, waits or failed, the
    /// headers are redrawn once a minute (a minute may show up to a minute late).
    private func keepMinutesFresh() {
        let needed = set.workspaces.flatMap(\.panes).contains { pane in
            pane.agent.map { $0.state.kind != .stopped } ?? false
        }
        guard needed != (minuteTicker != nil) else { return }
        minuteTicker?.cancel()
        minuteTicker =
            needed
            ? Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.minute)
                    guard !Task.isCancelled, let self else { return }
                    self.onChange?(self.state)
                }
            } : nil
    }

    private static let minute: Duration = .seconds(60)
}

/// Install and uninstall share one shape, so the palette runs either the same way.
@MainActor
protocol IntegrationCommand {
    init(integration: any HarnessIntegration, id: IntegrationID, texts: IntegrationTexts)
    func execute() async -> String
}

extension InstallClaudeIntegration: IntegrationCommand {}
extension UninstallClaudeIntegration: IntegrationCommand {}

/// F6: the editor coordinator works on this window's panes.
extension TilingController: EditorHost {
    func panes(nearEditorOf pane: PaneID) -> [Pane] {
        set.workspaces.first { workspace in workspace.panes.contains { $0.id == pane } }?.panes ?? []
    }

    func pane(byID id: PaneID) -> Pane? { pane(id) }

    func report(_ text: String) { show(.editor(text)) }

    func openEditorPane(command: String, directory: WorkingDirectory, beside: PaneID) -> PaneID? {
        let request = OpenPaneRequest(
            shell: config.shell, geometry: geometry, home: deps.home, directory: directory, initialInput: command + "\n"
        )
        do {
            let pane = try OpenPane(engine: deps.engine, environment: deps.paneEnvironment).execute(request, in: &set)
            observe(pane)
            publish()
            return pane
        } catch {
            show(Self.message(for: error))
            return nil
        }
    }
}

/// F6: what every window's Neovim panes share.
struct EditorSettings {
    let editedFiles: TrackEditedFiles
    let nvim: String
    let socketDirectory: String
    /// The composition root's Neovim adapter.
    let bridge: any EditorBridge
    /// claudecode.nvim is installed right now: Claude relaunched by Smalti (restore, search) adds `--ide`.
    let connectsEditor: () -> Bool
}
