import Foundation
import OSLog
import SmaltiCore

/// The engine as the app needs it: the domain port plus the view of each pane.
typealias PaneEngine = TerminalEngine & TerminalViewProvider

/// What the views draw after every change.
struct TilingState {
    let set: WorkspaceSet
    let config: SmaltiConfig
    let theme: Theme
    let message: StatusMessage?
    /// Directories show relative to it (`~/dev/xolken`).
    let home: WorkingDirectory
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
        let agents: AgentDependencies
        let home: WorkingDirectory
        let shellOverride: TerminalCommand?
        /// Reloads the terminal engine's appearance ("Recargar configuración").
        let applyAppearance: (TerminalAppearance) throws(TerminalEngineError) -> Void
    }

    /// What agent events need from outside the tiling.
    struct AgentDependencies {
        let notifier: any Notifier
        let integration: any HarnessIntegration
        let isAppActive: () -> Bool
    }

    var onChange: ((TilingState) -> Void)?
    /// Supplies the pane area of the grid; the views own geometry.
    var area: () -> Rect = { .zero }
    /// Commands that open UI instead of changing tiling (the palette, the rename prompt) go to the views.
    var onViewCommand: ((CommandID) -> Void)?

    private let deps: Dependencies
    private let layouts = LayoutCatalog.standard
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "tiling")
    private(set) var set: WorkspaceSet
    private(set) var config: SmaltiConfig
    private var status = StatusSlot<StatusMessage>()
    private var messageClearing: Task<Void, Never>?
    private var openedAt: [PaneID: ContinuousClock.Instant] = [:]
    /// `restore` signpost: ends when every restored pane's shell reported its directory (it is interactive).
    private let signposter = OSSignposter(subsystem: AppIdentity.current.bundleIdentifier, category: "restore")
    private var pendingRestore: (interval: OSSignpostIntervalState, panes: Set<PaneID>)?
    private var minuteTicker: Task<Void, Never>?

    /// `initial` is the startup load, done before the engine exists because the engine needs its appearance.
    init(_ deps: Dependencies, initial reload: ConfigReload) {
        self.deps = deps
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        let layout = LayoutCatalog.standard.strategyOrDefault(for: config.defaultLayout)
        set = WorkspaceSet(first: .empty(name: deps.home.lastComponent, rootDirectory: deps.home, layout: layout))
        status = status.withPersistent(reload.error.map(StatusMessage.invalidConfig))
    }

    var theme: Theme { Theme.obsidian.applying(config.appearance) }

    var home: WorkingDirectory { deps.home }

    var geometry: LayoutGeometry {
        LayoutGeometry(area: area(), gap: theme.panel.gap, minimumPaneSize: LayoutGeometry.standardMinimumPaneSize)
    }

    /// Opens the first pane of the first workspace.
    func start() {
        openPane()
        publish()
    }

    /// Starts from what the last run left: a fresh window, or the restored workspaces.
    func start(from choice: StartupChoice, onAsk: (SessionSnapshot) -> Void) {
        switch choice {
        case .startFresh:
            start()
        case .startFreshAfterUnreadable(let reason):
            start()
            report(.unreadableSession(reason))
        case .restoreAll(let snapshot):
            restore(snapshot, mode: .full, selection: .defaults(for: snapshot))
        case .ask(let snapshot):
            onAsk(snapshot)
        }
    }

    /// An agent's hook event, from the IPC socket.
    func handle(_ event: AgentEvent) {
        _ = HandleAgentEvent(notifier: deps.agents.notifier).execute(
            event, in: &set, isAppActive: deps.agents.isAppActive())
        publish()
    }

    /// A click on a notification: show its pane (switching workspace); if it is gone, only the app comes forward.
    func activate(_ pane: PaneID) {
        guard ActivatePane(engine: deps.engine).execute(pane, in: &set) else { return }
        publish()
    }

    private func jumpToWaitingAgent() {
        if JumpToWaitingAgent(engine: deps.engine).execute(in: &set) == .nobodyWaiting { show(.nobodyWaiting) }
    }

    private func runIntegration(_ command: IntegrationCommand.Type) {
        let integration = deps.agents.integration
        Task { [weak self] in
            let line = await command.init(integration: integration).execute()
            self?.report(.integration(line))
        }
    }

    /// The saved layouts as the palette lists them.
    func savedLayouts() -> [NamedLayoutSummary] {
        deps.namedLayouts.names().compactMap { name in
            (try? deps.namedLayouts.layout(named: name)).map { NamedLayoutSummary(name: name, layout: $0) }
        }
    }

    private func perform(_ command: NamedLayoutCommand) {
        switch command {
        case .save(let name):
            do {
                try SaveNamedLayout(layouts: deps.namedLayouts).execute(set.active, as: name)
                show(.layoutSaved(name.rawValue))
            } catch {
                show(.layoutSaveFailed(name.rawValue, reason: error.summary))
            }
        case .restore(let name): restoreLayout(name)
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
            show(.layoutRestoreFailed(name.rawValue, reason: error.summary))
        }
    }

    private var restoreSession: RestoreSession {
        RestoreSession(
            .init(
                engine: deps.engine, transcripts: deps.transcripts, harnesses: deps.harnesses,
                environment: deps.paneEnvironment, shell: config.shell, clock: { .now }))
    }

    /// Rebuilds the saved workspaces; if none could open, starts as usual.
    func restore(_ snapshot: SessionSnapshot, mode: RestoreMode, selection: RestoreSelection) {
        let interval = signposter.beginInterval("restore", id: signposter.makeSignpostID())
        let plan = RestorePlan.make(from: snapshot, mode: mode, selection: selection)
        let result = restoreSession.execute(plan, savedAt: snapshot.savedAt, home: deps.home)
        guard let restored = result.set else {
            signposter.endInterval("restore", interval)
            start()
            reportRestoreFailures(result.failures)
            return
        }
        set = restored
        pendingRestore = (interval, Set(set.workspaces.flatMap(\.panes).map(\.id)))
        set.workspaces.flatMap(\.panes).forEach { observe($0.id) }
        reportRestoreFailures(result.failures)
        publish()
    }

    func perform(_ command: CommandID) {
        if Self.viewCommands.contains(command) {
            onViewCommand?(command)
            return
        }
        guard let action = action(for: command) else {
            logger.error("unknown command \(command.rawValue, privacy: .public)")
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

    private static let viewCommands: Set<CommandID> = [.paletteOpen, .workspaceRename]

    private func action(for command: CommandID) -> (() -> Void)? {
        if let action = fixedActions[command] { return action }
        if let named = command.namedLayout { return { [unowned self] in perform(named) } }
        if let action = layoutActions[command] { return action }
        return workspaceGoAction(command)
    }

    /// Built once: the closures read the controller's state when they run, not when they are built.
    /// `unowned` is safe because the controller owns them.
    private lazy var fixedActions: [CommandID: () -> Void] = {
        var actions: [CommandID: () -> Void] = [
            .paneNew: { [unowned self] in openPane() },
            .paneClose: { [unowned self] in closeFocusedPane() },
            .panesEqualize: { [unowned self] in EqualizePanes().execute(in: &set) },
            .workspaceNew: { [unowned self] in createWorkspace() },
            .workspaceClose: { [unowned self] in closeActiveWorkspace() },
            .configReload: { [unowned self] in reloadConfig() },
            .agentJump: { [unowned self] in jumpToWaitingAgent() },
            .claudeIntegrationInstall: { [unowned self] in runIntegration(InstallClaudeIntegration.self) },
            .claudeIntegrationUninstall: { [unowned self] in runIntegration(UninstallClaudeIntegration.self) },
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
        let request = OpenPaneRequest(shell: config.shell, geometry: geometry)
        do {
            let pane = try OpenPane(engine: deps.engine, environment: deps.paneEnvironment).execute(request, in: &set)
            observe(pane)
        } catch {
            show(Self.message(for: error))
        }
    }

    private func createWorkspace() {
        let layout = layouts.strategyOrDefault(for: config.defaultLayout)
        let request = CreateWorkspaceRequest(
            pane: OpenPaneRequest(shell: config.shell, geometry: geometry), layout: layout)
        do {
            _ = try CreateWorkspace(engine: deps.engine, environment: deps.paneEnvironment).execute(request, in: &set)
            set.active.panes.forEach { observe($0.id) }
        } catch {
            show(Self.message(for: error))
        }
    }

    private func closeFocusedPane() {
        guard let pane = set.active.focusedPane else { return }
        close(pane)
    }

    private func close(_ pane: PaneID) {
        _ = ClosePane(engine: deps.engine).execute(pane, in: &set)
        openedAt[pane] = nil
    }

    /// The only workspace cannot close; a shortcut bound in config.toml can still ask, and the refusal leaves
    /// everything as it was (the palette does not offer the command then).
    private func closeActiveWorkspace() {
        do {
            let closed = try CloseWorkspace(engine: deps.engine).execute(set.activeID, in: &set)
            closed.forEach { openedAt[$0] = nil }
        } catch {
            switch error {
            case .cannotCloseLastWorkspace: logger.debug("refused to close the last workspace")
            }
        }
    }

    private func reloadConfig() {
        let reload = ReloadConfig(store: deps.configStore).execute()
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        if let error = reload.error {
            show(.invalidConfig(error))
            return
        }
        status = status.withPersistent(nil)
        do {
            try deps.applyAppearance(theme.terminal)
        } catch {
            show(.engineFailure(error))
        }
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
        if case .workingDirectoryChanged = event { restoredPaneIsInteractive(pane) }
        switch event {
        case .exited(let code): paneExited(pane, code: code)
        case .closeRequested: close(pane)
        default:
            guard let owner = set.workspace(containing: pane) else { return }
            set = set.updating(owner) { $0.applying(event, to: pane, at: .now) }
        }
        publish()
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
        onChange?(TilingState(set: set, config: config, theme: theme, message: status.showing, home: deps.home))
        keepMinutesFresh()
    }

    /// "te espera · 2m" counts minutes: while an agent waits or failed, the headers are redrawn once a minute.
    private func keepMinutesFresh() {
        let needed = !AttentionQueue.panes(in: set).isEmpty
        guard needed != (minuteTicker != nil) else { return }
        minuteTicker?.cancel()
        minuteTicker =
            needed
            ? Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.minute)
                    guard !Task.isCancelled, let self else { return }
                    self.onChange?(
                        TilingState(
                            set: self.set, config: self.config, theme: self.theme, message: self.status.showing,
                            home: self.deps.home))
                }
            } : nil
    }

    private static let minute: Duration = .seconds(60)
}

/// Install and uninstall share one shape, so the palette runs either the same way.
@MainActor
protocol IntegrationCommand {
    init(integration: any HarnessIntegration)
    func execute() async -> String
}

extension InstallClaudeIntegration: IntegrationCommand {}
extension UninstallClaudeIntegration: IntegrationCommand {}
