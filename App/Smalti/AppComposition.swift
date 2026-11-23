import AppKit
import ClaudeHarnessAdapter
import ClaudeTelemetryAdapter
import DarwinMetricsAdapter
import FigCompletionAdapter
import FileSessionAdapter
import GhosttyAdapter
import IPCAdapter
import OllamaAdapter
import ProjectContextAdapter
import UserNotificationsAdapter
import OSLog
import SmaltiCore
import TOMLConfigAdapter

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "engine")
    private var runtime: GhosttyRuntime?
    private var engine: GhosttyTerminalEngine?
    private var sessionKeeper: SessionKeeper?
    /// F4.5: every window, in opening order, and the one in front (the last key window).
    private var compositions: [WindowComposition] = []
    private var frontID: WindowID?
    private var front: WindowComposition? { compositions.first { $0.id == frontID } ?? compositions.last }
    private var controller: TilingController? { front?.controller }
    /// What every window's controller is built with; set once the engine exists.
    private var controllerDependencies: TilingController.Dependencies?
    private var configStore: TOMLConfigStore?
    private var restorePreferences: (any RestorePreferenceStore)?
    private var stateDirectoryForTests: String?
    private var telemetry: UnixSocketTelemetry?
    private var observatory: ObservatoryRefresher?
    private var input: InputCoordinator?
    private var completionMenu: CompletionMenuController?
    private var historyPalette: HistoryPaletteController?
    private var transcripts: ClaudeTranscripts?
    private let harnesses = HarnessRegistry([ClaudeHarness()])
    private static let persistTimeout: Duration = .seconds(1)

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
        // Development builds state their state directory so UI tests can check they never use the user's.
        if AppIdentity.current.isDevelopment {
            stateDirectoryForTests = startup.settings.stateDirectory.path(percentEncoded: false)
        }
        do {
            try start(startup)
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
    /// Claude Code's `CLAUDE_CONFIG_DIR` rides along in the same map (LaunchSettings keeps three parameters).
    private static func launchArguments() -> [String: String] {
        let keys = [
            LaunchSettings.configPathKey, LaunchSettings.shellCommandKey, LaunchSettings.statePathKey,
            LaunchSettings.claudeHomeKey, LaunchSettings.ollamaURLKey, LaunchSettings.userZdotdirKey,
        ]
        var arguments = keys.reduce(into: [String: String]()) { $0[$1] = UserDefaults.standard.string(forKey: $1) }
        arguments[LaunchSettings.claudeConfigDirKey] =
            ProcessInfo.processInfo.environment[LaunchSettings.claudeConfigDirKey]
        return arguments
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

    private func start(_ startup: Startup) throws(TerminalEngineError) {
        let runtime = try makeRuntime(
            startup.theme.terminal, configFile: startup.settings.stateDirectory.appending(path: "ghostty.conf"))
        let state = startup.settings.stateDirectory
        let engine = GhosttyTerminalEngine(
            runtime: runtime, zshDirectory: state.appending(path: "zsh"),
            userZdotdir: startup.settings.userZdotdir ?? ProcessInfo.processInfo.environment["ZDOTDIR"])
        let archive = FileSessionArchive(directory: state)
        let socket = SocketLocation.socketFile(
            stateDirectory: state, temporaryDirectory: FileManager.default.temporaryDirectory)
        let inputSettings = startup.initial.config.input
        let inputSocket =
            inputSettings.isEnabled
            ? SocketLocation.socketFile(
                named: "input", stateDirectory: state, temporaryDirectory: FileManager.default.temporaryDirectory)
            : nil
        let environment = PaneEnvironment(
            version: Self.version, extra: ["SMALTI_GHOST_COLOR": startup.theme.text.ghostText.hexString],
            files: PaneFileLocator(stateDirectory: state),
            ipc: Self.ipcEndpoints(socket: socket, inputSocket: inputSocket))
        let dependencies = TilingController.Dependencies(
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
            })
        controllerDependencies = dependencies
        configStore = startup.store
        restorePreferences = archive
        let controller = TilingController(dependencies, initial: startup.initial)
        listenForAgents(on: socket, controller: controller)
        if let inputSocket { startInput(on: inputSocket, settings: inputSettings, startup: startup, engine: engine) }
        startObservatory(startup, controller: controller)
        let keeper = SessionKeeper(save: SaveSession(archive: archive, transcripts: archive, scrollback: engine))
        keeper.onFailure = { [weak controller] reason in controller?.report(.sessionSaveFailed(reason)) }
        self.runtime = runtime
        self.engine = engine
        sessionKeeper = keeper
        let composition = makeComposition(controller, engine: engine)
        switch LoadLastSession(archive: archive, preferences: archive).execute() {
        case .startFresh:
            controller.start()
        case .startFreshAfterUnreadable(let reason):
            controller.start()
            controller.report(.unreadableSession(reason))
        case .restoreAll(let snapshot):
            restoreWindows(snapshot, mode: .full, selection: .defaults(for: snapshot))
        case .ask(let snapshot):
            composition.ask(snapshot, preferences: archive)
        }
        // While the resume screen asks, nothing is saved: quitting there keeps the last session.
        if !composition.isAskingToRestore { beginSaving(keepingPreviousSession: false) }
    }

    // MARK: - Windows (F4.5)

    /// A window for `controller`, cascaded from the front one, in front. Its controller has not opened panes yet.
    @discardableResult
    private func makeComposition(_ controller: TilingController, engine: GhosttyTerminalEngine) -> WindowComposition {
        let window = SmaltiWindow(theme: controller.theme)
        if let frame = front?.window.frame {
            let next = WindowFrame.cascaded(
                from: Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
            window.setFrameOrigin(NSPoint(x: next.minX, y: next.minY))
        }
        window.makeKeyAndOrderFront(nil)
        if let path = stateDirectoryForTests { window.setAccessibilityValue(path) }
        let composition = WindowComposition(window: window, controller: controller, services: windowServices(engine))
        compositions.append(composition)
        frontID = composition.id
        window.contentView?.layoutSubtreeIfNeeded()
        return composition
    }

    /// A new window with a fresh controller; nil before the engine exists.
    private func makeWindow() -> WindowComposition? {
        guard let dependencies = controllerDependencies, let store = configStore, let engine else { return nil }
        return makeComposition(
            TilingController(dependencies, initial: ReloadConfig(store: store).execute()), engine: engine)
    }

    /// Every window as the session sees it, the front one marked; nil with no windows.
    private func windowSet() -> WindowSet? {
        guard let first = compositions.first else { return nil }
        let set = compositions.dropFirst().reduce(WindowSet(first: first.state)) { $0.opening($1.state) }
        return set.bringingToFront(front?.id ?? first.id)
    }

    private func windowsChanged() {
        guard let set = windowSet() else { return }
        sessionKeeper?.changed(set)
        input?.keepOnly(Set(set.allPanes.map(\.id)))
    }

    private func composition(containing pane: PaneID) -> WindowComposition? {
        compositions.first { $0.controller.set.workspace(containing: pane) != nil }
    }

    private func perform(_ command: CommandID, from composition: WindowComposition) {
        switch command {
        case .windowNew: openWindow(from: composition)
        case .windowClose: closeWindow(composition)
        case .windowFullscreen: composition.window.toggleFullScreen(nil)
        case .windowMinimize: composition.window.miniaturize(nil)
        case .agentJump: jumpToWaitingAgent(from: composition)
        case .configReload: compositions.forEach { $0.controller.reloadConfig() }
        default: break
        }
    }

    /// ⌘N: a window with one pane in the directory a new pane of `origin` would open in.
    private func openWindow(from origin: WindowComposition?) {
        let directory = origin?.controller.set.active.directoryForNewPane ?? controller?.home
        guard let directory, let window = makeWindow() else { return }
        window.controller.start(in: directory)
    }

    /// ⇧⌘W: closes the window and its panes, after asking if something runs in it; the last window quits instead
    /// (which asks about the whole app and saves it).
    private func closeWindow(_ composition: WindowComposition) {
        guard compositions.count > 1 else {
            NSApp.terminate(nil)
            return
        }
        let busy = CloseGuard.busyPanes(composition.controller.set.workspaces.flatMap(\.panes))
        guard
            let question = CloseGuard.question(for: .window, busy: busy, settings: composition.controller.config.window)
        else {
            close(composition)
            return
        }
        CloseConfirmation.ask(question, in: composition.window) { [weak self, weak composition] confirmed in
            guard confirmed, let composition else { return }
            self?.close(composition)
        }
    }

    private func close(_ composition: WindowComposition) {
        guard var set = windowSet(), let engine else { return }
        guard CloseWindow(engine: engine).execute(composition.id, in: &set) == .closed else {
            NSApp.terminate(nil)
            return
        }
        compositions.removeAll { $0 === composition }
        composition.window.close()
        frontID = set.frontID
        front?.window.makeKeyAndOrderFront(nil)
        windowsChanged()
    }

    /// ⌘J: the window it came from first, then the others; the one with a waiting agent comes to the front.
    private func jumpToWaitingAgent(from origin: WindowComposition) {
        let order = [origin] + compositions.filter { $0 !== origin }
        guard let found = order.first(where: { $0.controller.jumpToWaitingAgent() }) else {
            origin.controller.reportNobodyWaiting()
            return
        }
        found.window.makeKeyAndOrderFront(nil)
    }

    /// Rebuilds every saved window: the first in the window that is already open, the rest in new ones, each at its
    /// saved frame refitted to the screens there are now. A later window with nothing chosen is not opened.
    private func restoreWindows(_ snapshot: SessionSnapshot, mode: RestoreMode, selection: RestoreSelection) {
        var inFront: WindowComposition?
        for (index, saved) in snapshot.windows.enumerated() {
            let plan = RestorePlan.make(from: saved, mode: mode, selection: selection)
            guard index == 0 || !plan.workspaces.isEmpty else { continue }
            guard let composition = index == 0 ? compositions.first : makeWindow() else { continue }
            if let frame = saved.frame { composition.place(at: frame) }
            composition.controller.restore(plan, savedAt: snapshot.savedAt)
            if saved.isFullScreen { composition.window.toggleFullScreen(nil) }
            if index == snapshot.frontIndex { inFront = composition }
        }
        inFront?.window.makeKeyAndOrderFront(nil)
    }

    private func restoreChosen(_ choice: RestoreChoice, snapshot: SessionSnapshot) {
        switch choice {
        case .restore(let selection):
            restoreWindows(snapshot, mode: .full, selection: selection)
        case .layoutsOnly:
            restoreWindows(snapshot, mode: .layoutsOnly, selection: .defaults(for: snapshot))
        case .startClean:
            front?.controller.start()
            beginSaving(keepingPreviousSession: true)
            return
        }
        beginSaving(keepingPreviousSession: false)
    }

    /// The Dock's menu: "Nueva ventana".
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        for item in MenuModel.dockMenu() {
            menu.addItem(
                ClosureMenuItem(title: item.title) { [weak self] in self?.openWindow(from: self?.front) })
        }
        return menu
    }

    private func windowServices(_ engine: GhosttyTerminalEngine) -> WindowServices {
        WindowServices(
            engine: engine, harnesses: harnesses,
            changed: { [weak self] in self?.windowsChanged() },
            restoreChosen: { [weak self] choice, snapshot in self?.restoreChosen(choice, snapshot: snapshot) },
            appCommand: { [weak self] command, composition in self?.perform(command, from: composition) },
            becameFront: { [weak self] composition in self?.frontID = composition.id },
            completionMenu: { [weak self] in self?.completionMenu },
            historyPalette: { [weak self] in self?.historyPalette },
            openHistory: { [weak self] pane in self?.input?.openHistory(for: pane) },
            observatoryOpenChanged: { [weak self] isOpen in self?.observatory?.isObservatoryOpen = isOpen })
    }

    /// A second instance of this build (its socket was taken) never saves: it would overwrite the first one's
    /// session and prune its scrollback.
    private func beginSaving(keepingPreviousSession: Bool) {
        guard telemetry != nil, let keeper = sessionKeeper, let set = windowSet() else { return }
        keepingPreviousSession ? keeper.startKeepingPreviousSession(with: set) : keeper.start(with: set)
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
                guard let front = self?.composition(containing: pane) ?? self?.front else { return }
                if front.window.isMiniaturized { front.window.deminiaturize(nil) }
                front.window.makeKeyAndOrderFront(nil)
                front.dismissObservatory()
                front.controller.activate(pane)
            },
            onDenied: { [weak self] in self?.controller?.report(.notificationsDisabled) })
    }

    /// The observatory's sources: Claude's transcripts and session registry, Ollama and the machine (F3).
    private func startObservatory(_ startup: Startup, controller: TilingController) {
        let settings = startup.settings
        // A second instance of this build (its socket was taken) never writes the first one's state.
        let indexFile =
            telemetry == nil
            ? FileManager.default.temporaryDirectory.appending(path: "smalti-observatory-\(UUID().uuidString).json")
            : settings.stateDirectory.appending(path: "observatory/index.json")
        let transcripts = ClaudeTranscripts(claudeHome: settings.claudeHome, indexFile: indexFile, now: { .now })
        self.transcripts = transcripts
        let sources = ObservatorySources(
            transcripts: transcripts,
            live: ClaudeSessionRegistry(claudeHome: settings.claudeHome),
            localModels: OllamaLocalModels(baseURL: settings.ollamaURL), system: DarwinSystemMetrics(),
            catalog: startup.initial.config.observatory.catalog,
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
        let refresher = ObservatoryRefresher(
            observe: ObserveAgents(sources),
            callbacks: .init(
                panes: { [weak self] in self?.compositions.flatMap { PaneAgent.all(in: $0.controller.set) } ?? [] },
                onSnapshot: { [weak self] frame in self?.compositions.forEach { $0.show(frame) } },
                onError: { [weak controller] in controller?.report(.transcriptsUnreadable($0)) }))
        refresher.start()
        observatory = refresher
    }

    /// Hooks reach the app through `<state>/smalti.sock`. If another instance of this build owns it, this one runs
    /// without agent states and says so.
    private func listenForAgents(on socket: URL, controller: TilingController) {
        do {
            let telemetry = try UnixSocketTelemetry(socketFile: socket, clock: { .now })
            self.telemetry = telemetry
            let events = telemetry.events()
            Task { [weak self] in
                for await event in events {
                    // The window that holds the pane applies it; the others ignore a pane they do not have.
                    self?.compositions.forEach { $0.controller.handle(event) }
                    self?.observatory?.agentEvent(event)
                }
            }
        } catch IPCError.socketInUse {
            controller.report(.agentSocketInUse)
        } catch {
            logger.error("agent socket unavailable: \(String(describing: error), privacy: .public)")
            controller.report(.agentSocketFailed(String(describing: error)))
        }
    }

    /// F4: the input session over its adapters, and the socket every pane's zsh connects to. User specs live next
    /// to the config file (`~/.config/smalti/completions`), so UI tests with a temporary config never read the real
    /// ones.
    private func startInput(on socket: URL, settings: InputSettings, startup: Startup, engine: GhosttyTerminalEngine) {
        let state = startup.settings.stateDirectory
        let ports = InputSession.Ports(
            history: FileCommandHistory(
                file: state.appending(path: "input/history.jsonl"), limit: settings.historyLimit),
            project: FileProjectContext(),
            completions: FigSpecs(
                user: startup.settings.configFile.deletingLastPathComponent().appending(path: "completions"),
                runner: GeneratorRunner(timeout: settings.generatorTimeout)),
            predictor: HeuristicPredictor())
        let session = InputSession(ports: ports, settings: settings, clock: { .now })
        let coordinator = InputCoordinator(session: session, provider: engine) { [weak self] pane in
            self?.composition(containing: pane)?.controller.set.workspaces.lazy.flatMap(\.panes)
                .first { $0.id == pane }?.workingDirectory.path
        }
        do {
            try coordinator.start(socketFile: socket)
            input = coordinator
            completionMenu = CompletionMenuController(
                coordinator: coordinator, provider: engine,
                theme: { [weak self] in self?.controller?.theme ?? startup.theme })
            historyPalette = HistoryPaletteController(
                coordinator: coordinator, provider: engine,
                context: (
                    theme: { [weak self] in self?.controller?.theme ?? startup.theme },
                    onOpen: { [weak self] in self?.completionMenu?.close() },
                    returnFocus: { [weak self] pane in self?.front?.focusKeyboard(on: pane) }
                ))
        } catch {
            logger.error("input socket unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private static func ipcEndpoints(socket: URL, inputSocket: URL?) -> IPCEndpoints? {
        guard let cli = Bundle.main.resourceURL?.appending(path: "bin/smalti"),
            FileManager.default.isExecutableFile(atPath: cli.path(percentEncoded: false))
        else { return nil }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return IPCEndpoints(socket: socket, cli: cli, inheritedPath: path, inputSocket: inputSocket)
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

    /// ⌘Q: asks in the front window when something runs in any window or workspace; `answer` gets the choice (true
    /// at once when nothing runs).
    func confirmQuit(_ answer: @escaping (Bool) -> Void) {
        guard let windows = windowSet(), let front, let settings = controller?.config.window else {
            answer(true)
            return
        }
        let busy = CloseGuard.busyPanes(in: windows)
        let count = CloseGuard.windowsWithBusyPanes(busy, in: windows)
        guard let question = CloseGuard.question(for: .quit(windowCount: count), busy: busy, settings: settings) else {
            answer(true)
            return
        }
        CloseConfirmation.ask(question, in: front.window, then: answer)
    }

    /// `applicationShouldTerminate`: saves everything, scrollback included, before the app quits.
    func saveForQuit() {
        windowsChanged()
        sessionKeeper?.saveForQuit()
        telemetry?.stop()
        observatory?.stop()
        input?.stop()
    }

    /// Writes the transcripts index's pending changes, giving up after a second so quitting never hangs.
    func persistObservatory() async {
        guard let transcripts else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await transcripts.persistIndex() }
            group.addTask { try? await Task.sleep(for: Self.persistTimeout) }
            await group.next()
            group.cancelAll()
        }
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
