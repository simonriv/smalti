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
}

/// Primary adapter between AppKit and the use cases: turns a `CommandID` (from a shortcut, the palette or a click)
/// and every terminal event into one use case call, then publishes the new state. It holds no tiling rules.
@MainActor
final class TilingController {
    struct Dependencies {
        let engine: any PaneEngine
        let configStore: any ConfigStore
        let version: String
        let home: WorkingDirectory
        let shellOverride: TerminalCommand?
        /// Reloads the terminal engine's appearance ("Recargar configuración").
        let applyAppearance: (TerminalAppearance) throws(TerminalEngineError) -> Void
    }

    var onChange: ((TilingState) -> Void)?
    /// Supplies the pane area of the grid; the views own geometry.
    var area: () -> Rect = { Rect(x: 0, y: 0, width: 0, height: 0) }

    private let deps: Dependencies
    private let layouts = LayoutCatalog.standard
    private let logger = Logger(subsystem: "dev.simonriv.smalti", category: "tiling")
    private(set) var set: WorkspaceSet
    private(set) var config: SmaltiConfig
    private var message: StatusMessage?
    private var messageClearing: Task<Void, Never>?
    private var openedAt: [PaneID: ContinuousClock.Instant] = [:]

    /// `initial` is the startup load, done before the engine exists because the engine needs its appearance.
    init(_ deps: Dependencies, initial reload: ConfigReload) {
        self.deps = deps
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        let layout = LayoutCatalog.standard.strategy(for: config.defaultLayout) ?? DwindleLayout()
        set = WorkspaceSet(first: .empty(name: deps.home.lastComponent, rootDirectory: deps.home, layout: layout))
        message = reload.error.map(StatusMessage.invalidConfig)
    }

    var theme: Theme { Theme.obsidian.applying(config.appearance) }

    var geometry: LayoutGeometry {
        LayoutGeometry(area: area(), gap: theme.panel.gap, minimumPaneSize: LayoutGeometry.standardMinimumPaneSize)
    }

    /// Opens the first pane of the first workspace.
    func start() {
        openPane()
        publish()
    }

    func perform(_ command: CommandID) {
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

    func rename(to name: String) {
        RenameWorkspace().execute(name, in: &set)
        publish()
    }

    // MARK: - Commands

    private func action(for command: CommandID) -> (() -> Void)? {
        if let action = fixedActions[command] { return action }
        if let action = layoutActions[command] { return action }
        return workspaceGoAction(command)
    }

    private var fixedActions: [CommandID: () -> Void] {
        var actions: [CommandID: () -> Void] = [
            .paneNew: { [unowned self] in openPane() },
            .paneClose: { [unowned self] in closeFocusedPane() },
            .panesEqualize: { [unowned self] in EqualizePanes().execute(in: &set) },
            .workspaceNew: { [unowned self] in createWorkspace() },
            .workspaceClose: { [unowned self] in closeActiveWorkspace() },
            .configReload: { [unowned self] in reloadConfig() },
        ]
        for number in 1...9 {
            actions[.paneFocus(number)] = { [unowned self] in
                FocusPane().execute(.index(number), geometry: geometry, in: &set)
            }
            actions[.workspace(number)] = { [unowned self] in
                SwitchWorkspace(engine: deps.engine).execute(.index(number), in: &set)
            }
        }
        for direction in Direction.allCases { actions.merge(directionActions(direction)) { $1 } }
        return actions
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
        let request = OpenPaneRequest(shell: config.shell, geometry: geometry)
        do {
            let pane = try OpenPane(engine: deps.engine, version: deps.version).execute(request, in: &set)
            observe(pane)
        } catch {
            show(Self.message(for: error))
        }
    }

    private func createWorkspace() {
        let layout = layouts.strategy(for: config.defaultLayout) ?? DwindleLayout()
        let request = CreateWorkspaceRequest(
            pane: OpenPaneRequest(shell: config.shell, geometry: geometry), layout: layout)
        do {
            _ = try CreateWorkspace(engine: deps.engine, version: deps.version).execute(request, in: &set)
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

    /// Closing the only workspace is not offered (the catalog hides it), so the refusal needs no message.
    private func closeActiveWorkspace() {
        try? CloseWorkspace(engine: deps.engine).execute(set.activeID, in: &set)
    }

    private func reloadConfig() {
        let reload = ReloadConfig(store: deps.configStore).execute()
        config = reload.config.withShell(overriddenBy: deps.shellOverride)
        if let error = reload.error {
            show(.invalidConfig(error))
            return
        }
        message = nil
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
        switch event {
        case .exited(let code): paneExited(pane, code: code)
        case .closeRequested: close(pane)
        default:
            guard let owner = set.workspace(containing: pane) else { return }
            set = set.updating(owner) { $0.applying(event, to: pane) }
        }
        publish()
    }

    private func paneExited(_ pane: PaneID, code: Int?) {
        let lifetime = openedAt[pane].map { ContinuousClock.now - $0 } ?? .zero
        openedAt[pane] = nil
        let outcome = HandlePaneExit(engine: deps.engine).execute(
            PaneExit(pane: pane, exitCode: code, lifetime: lifetime), in: &set)
        if case .closedAfterFailedStart(let exitCode) = outcome { show(.failedStart(exitCode: exitCode)) }
    }

    // MARK: - Publishing

    private func show(_ newMessage: StatusMessage) {
        message = newMessage
        messageClearing?.cancel()
        guard newMessage.isTransient else { return }
        messageClearing = Task { [weak self] in
            try? await Task.sleep(for: StatusMessage.transientDuration)
            guard !Task.isCancelled, let self, self.message == newMessage else { return }
            self.message = nil
            self.publish()
        }
    }

    private func publish() {
        onChange?(TilingState(set: set, config: config, theme: theme, message: message))
    }
}
