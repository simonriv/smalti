import AppKit
import ClaudeHarnessAdapter
import FileSessionAdapter
import GhosttyAdapter
import IPCAdapter
import UserNotificationsAdapter
import OSLog
import SmaltiCore
import TOMLConfigAdapter

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "engine")
    private var window: SmaltiWindow?
    private var runtime: GhosttyRuntime?
    private var engine: GhosttyTerminalEngine?
    private var controller: TilingController?
    private var palette: CommandPaletteController?
    private var sessionKeeper: SessionKeeper?
    private var restoreScreen: RestoreController?
    private var telemetry: UnixSocketTelemetry?
    private let harnesses = HarnessRegistry([ClaudeHarness()])
    /// What the glass was last painted with, so a publish that does not change it repaints nothing.
    private var appliedWindowTokens: WindowTokens?

    /// What startup reads before any infrastructure exists: launch arguments, the store and its first load.
    private struct Startup {
        let settings: LaunchSettings
        let store: TOMLConfigStore
        let initial: ConfigReload
        let theme: Theme
    }

    func showMainWindow() {
        AppFonts.registerBundled()
        let startup = Self.readStartup()
        let window = SmaltiWindow(theme: startup.theme)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        // Development builds state their state directory so UI tests can check they never use the user's.
        if AppIdentity.current.isDevelopment {
            window.setAccessibilityValue(startup.settings.stateDirectory.path(percentEncoded: false))
        }
        applyGlass(startup.theme, to: window)
        do {
            try start(startup, in: window)
        } catch {
            fail(error)
        }
    }

    private static func readStartup() -> Startup {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = LaunchSettings(
            arguments: launchArguments(), home: home,
            defaultStateDirectory: AppIdentity.current.defaultStateDirectory(home: home))
        createStateDirectory(settings.stateDirectory)
        let store = TOMLConfigStore(file: settings.configFile)
        let initial = ReloadConfig(store: store).execute()
        return Startup(
            settings: settings, store: store, initial: initial,
            theme: Theme.obsidian.applying(initial.config.appearance))
    }

    /// `-Key value` launch arguments land in the argument domain of the user defaults.
    private static func launchArguments() -> [String: String] {
        let keys = [LaunchSettings.configPathKey, LaunchSettings.shellCommandKey, LaunchSettings.statePathKey]
        return keys.reduce(into: [:]) { arguments, key in arguments[key] = UserDefaults.standard.string(forKey: key) }
    }

    /// Owner-only (0700), also when it already existed: it holds scrollback and the IPC socket. A failure is logged;
    /// saving reports it later.
    private static func createStateDirectory(_ directory: URL) {
        let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: ownerOnly)
            try FileManager.default.setAttributes(ownerOnly, ofItemAtPath: directory.path(percentEncoded: false))
        } catch {
            Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "state")
                .error("could not create the state directory \(directory.path(percentEncoded: false)): \(error)")
        }
    }

    private func start(_ startup: Startup, in window: SmaltiWindow) throws(TerminalEngineError) {
        let runtime = try makeRuntime(
            startup.theme.terminal, configFile: startup.settings.stateDirectory.appending(path: "ghostty.conf"))
        let state = startup.settings.stateDirectory
        let engine = GhosttyTerminalEngine(
            runtime: runtime, zshDirectory: state.appending(path: "zsh"),
            userZdotdir: ProcessInfo.processInfo.environment["ZDOTDIR"])
        let archive = FileSessionArchive(directory: state)
        let socket = SocketLocation.socketFile(
            stateDirectory: state, temporaryDirectory: FileManager.default.temporaryDirectory)
        let environment = PaneEnvironment(
            version: Self.version, files: PaneFileLocator(stateDirectory: state), ipc: Self.ipcEndpoints(socket: socket)
        )
        let controller = TilingController(
            .init(
                engine: engine, configStore: startup.store, paneEnvironment: environment, transcripts: archive,
                namedLayouts: archive,
                harnesses: harnesses,
                agents: .init(
                    notifier: makeNotifier(), integration: Self.claudeIntegration(),
                    isAppActive: { NSApp.isActive }),
                home: try homeDirectory(),
                shellOverride: startup.settings.shellOverride,
                applyAppearance: { [weak runtime] appearance throws(TerminalEngineError) in
                    try runtime?.apply(appearance)
                }),
            initial: startup.initial)
        listenForAgents(on: socket, controller: controller)
        let keeper = SessionKeeper(save: SaveSession(archive: archive, transcripts: archive, scrollback: engine))
        keeper.onFailure = { [weak controller] reason in controller?.report(.sessionSaveFailed(reason)) }
        connect(controller, to: window, engine: engine)
        self.runtime = runtime
        self.engine = engine
        self.controller = controller
        sessionKeeper = keeper
        window.contentView?.layoutSubtreeIfNeeded()
        let choice = LoadLastSession(archive: archive, preferences: archive).execute()
        controller.start(from: choice) { [weak self] snapshot in
            self?.ask(snapshot, preferences: archive, in: window)
        }
        // While the resume screen asks, nothing is saved: quitting there keeps the last session.
        if restoreScreen == nil { beginSaving(controller.set, keepingPreviousSession: false) }
    }

    /// A second instance of this build (its socket was taken) never saves: it would overwrite the first one's
    /// session and prune its scrollback.
    private func beginSaving(_ set: WorkspaceSet, keepingPreviousSession: Bool) {
        guard telemetry != nil, let keeper = sessionKeeper else { return }
        keepingPreviousSession ? keeper.startKeepingPreviousSession(with: set) : keeper.start(with: set)
    }

    /// "Retomar donde quedaste": shown instead of the strip and the panes until the user chooses.
    private func ask(_ snapshot: SessionSnapshot, preferences: any RestorePreferenceStore, in window: SmaltiWindow) {
        guard let controller else { return }
        guard let content = window.contentView else {
            // Without a place to ask, restore what the defaults would: never start empty over a saved session.
            controller.restore(snapshot, mode: .full, selection: .defaults(for: snapshot))
            return
        }
        let listing = RestoreController.Content(
            snapshot: snapshot,
            workspaces: ResumeListing.workspaces(
                in: snapshot, home: controller.home, harnesses: harnesses),
            closedAt: ClosedAtPhrase.text(closedAt: snapshot.savedAt, now: .now, calendar: .current))
        let screen = RestoreController(listing, theme: controller.theme, preferences: preferences) {
            [weak self] choice in self?.finishAsking(choice, snapshot: snapshot, in: window)
        }
        screen.view.frame = content.bounds
        screen.view.autoresizingMask = [.width, .height]
        content.addSubview(screen.view)
        setTilingHidden(true, in: window)
        window.makeFirstResponder(screen.view)
        restoreScreen = screen
    }

    private func finishAsking(_ choice: RestoreChoice, snapshot: SessionSnapshot, in window: SmaltiWindow) {
        guard let controller else { return }
        restoreScreen?.view.removeFromSuperview()
        restoreScreen = nil
        setTilingHidden(false, in: window)
        switch choice {
        case .restore(let selection): controller.restore(snapshot, mode: .full, selection: selection)
        case .layoutsOnly: controller.restore(snapshot, mode: .layoutsOnly, selection: .defaults(for: snapshot))
        case .startClean:
            controller.start()
            beginSaving(controller.set, keepingPreviousSession: true)
            return
        }
        beginSaving(controller.set, keepingPreviousSession: false)
    }

    private func setTilingHidden(_ hidden: Bool, in window: SmaltiWindow) {
        [window.strip, window.paneGrid, window.statusBar].forEach { $0.isHidden = hidden }
    }

    /// macOS notifications; `-SmaltiNotificationLog <file>` writes them to a file instead (UI tests). A click shows the
    /// pane: the closures reach the controller once it exists.
    private func makeNotifier() -> any Notifier {
        if let log = UserDefaults.standard.string(forKey: "SmaltiNotificationLog"), !log.isEmpty {
            return FileLogNotifier(file: URL(filePath: log))
        }
        return UserNotificationsNotifier(
            onActivate: { [weak self] pane in
                NSApp.activate()
                if self?.window?.isMiniaturized == true { self?.window?.deminiaturize(nil) }
                self?.window?.makeKeyAndOrderFront(nil)
                self?.controller?.activate(pane)
            },
            onDenied: { [weak self] in self?.controller?.report(.notificationsDisabled) })
    }

    /// Hooks reach the app through `<state>/smalti.sock`. If another instance of this build owns it, this one runs
    /// without agent states and says so.
    private func listenForAgents(on socket: URL, controller: TilingController) {
        do {
            let telemetry = try UnixSocketTelemetry(socketFile: socket, clock: { .now })
            self.telemetry = telemetry
            let events = telemetry.events()
            Task { [weak controller] in
                for await event in events { controller?.handle(event) }
            }
        } catch IPCError.socketInUse {
            controller.report(.agentSocketInUse)
        } catch {
            logger.error("agent socket unavailable: \(String(describing: error), privacy: .public)")
            controller.report(.agentSocketFailed(String(describing: error)))
        }
    }

    private static func ipcEndpoints(socket: URL) -> IPCEndpoints? {
        guard let cli = Bundle.main.resourceURL?.appending(path: "bin/smalti"),
            FileManager.default.isExecutableFile(atPath: cli.path(percentEncoded: false))
        else { return nil }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return IPCEndpoints(socket: socket, cli: cli, inheritedPath: path)
    }

    /// `claude` is wherever the user's interactive zsh puts it; `SMALTI=1` keeps that shell out of tmux.
    private static func claudeIntegration() -> ClaudePluginInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let source = Bundle.main.resourceURL?.appending(path: "claude-plugin") ?? home
        let environment = ProcessInfo.processInfo.environment.merging(["SMALTI": "1"]) { _, smalti in smalti }
        return ClaudePluginInstaller(
            pluginSource: source,
            installDirectory: home.appending(path: "Library/Application Support/Smalti/claude-plugin"),
            runner: ShellCommandRunner(shell: ["/bin/zsh", "-lic"], environment: environment))
    }

    /// `applicationShouldTerminate`: saves everything, scrollback included, before the app quits.
    func saveForQuit() {
        sessionKeeper?.saveForQuit()
        telemetry?.stop()
    }

    private func connect(_ controller: TilingController, to window: SmaltiWindow, engine: GhosttyTerminalEngine) {
        let grid = window.paneGrid
        controller.area = { [weak grid] in grid?.area ?? .zero }
        controller.onChange = { [weak self, weak window] state in
            guard let window else { return }
            self?.applyGlass(state.theme, to: window)
            window.strip.render(state)
            window.paneGrid.render(state) { engine.view(for: $0) }
            window.statusBar.render(state)
            self?.focusKeyboard(on: state.set.active.focusedPane)
            self?.sessionKeeper?.changed(state.set)
        }
        grid.onPaneClicked = { [weak controller] pane in controller?.focus(pane) }
        window.strip.onCommand = { [weak controller] command in controller?.perform(command) }
        connectPalette(controller, to: window)
        connectKeyboard(controller, to: window)
    }

    /// ⌘K and "Renombrar workspace…" open the palette; while it is open the panes dim and keep their processes.
    private func connectPalette(_ controller: TilingController, to window: SmaltiWindow) {
        let palette = CommandPaletteController(
            window: window,
            actions: .init(
                search: { [weak controller] query in
                    guard let controller else { return [] }
                    return SearchCommands(layouts: .standard).execute(
                        query, set: controller.set, keymap: controller.config.keys,
                        savedLayouts: controller.savedLayouts())
                },
                perform: { [weak controller] command in controller?.perform(command) },
                rename: { [weak controller] name in controller?.rename(to: name) },
                currentWorkspaceName: { [weak controller] in controller?.set.active.name ?? "" }))
        palette.onOpenChange = { [weak self, weak window, weak controller] isOpen in
            guard let window, let controller else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { self?.focusKeyboard(on: controller.set.active.focusedPane) }
        }
        controller.onViewCommand = { [weak palette, weak controller] command in
            guard let palette, let theme = controller?.theme else { return }
            command == .workspaceRename ? palette.beginRename(theme: theme) : palette.toggle(theme: theme)
        }
        self.palette = palette
    }

    private func connectKeyboard(_ controller: TilingController, to window: SmaltiWindow) {
        let router = KeyRouter(
            keymap: { [weak controller] in controller?.config.keys ?? .standard },
            allowing: { [weak self] in self?.palette?.isOpen == true ? [.paletteOpen] : nil },
            perform: { [weak controller] command in controller?.perform(command) })
        // The resume screen owns the keyboard: no tiling shortcut acts, and its own keys reach it untouched.
        window.routeKey = { [weak self] event, composing in
            self?.restoreScreen == nil && router.route(event, composing: composing)
        }
    }

    /// At startup and whenever "Recargar configuración" changes `glass_opacity` or `blur`.
    private func applyGlass(_ theme: Theme, to window: SmaltiWindow) {
        guard theme.window != appliedWindowTokens else { return }
        window.applyGlass(theme)
        appliedWindowTokens = theme.window
    }

    /// Keystrokes go to the focused pane's terminal.
    private func focusKeyboard(on pane: PaneID?) {
        guard palette?.isOpen != true, let window, let pane, let view = engine?.view(for: pane),
            window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)
    }

    /// `configFile` lives in this build's state directory, so a development build never rewrites the daily one's.
    private func makeRuntime(
        _ appearance: TerminalAppearance, configFile: URL
    ) throws(TerminalEngineError) -> GhosttyRuntime {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: Bundle.main.resourceURL?.appending(path: "ghostty"))
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(appearance), writingTo: configFile)
        return try GhosttyRuntime(config: config)
    }

    private func homeDirectory() throws(TerminalEngineError) -> WorkingDirectory {
        let path = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        do {
            return try WorkingDirectory(path: path)
        } catch {
            throw .surfaceCreationFailed(workingDirectory: path, reason: "home directory is not absolute")
        }
    }

    private func fail(_ error: TerminalEngineError) {
        logger.error("terminal engine failed: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Smalti no pudo iniciar la terminal"
        alert.informativeText = EngineErrorText.describe(error)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
