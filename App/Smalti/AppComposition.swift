import AppKit
import AntigravityHarnessAdapter
import ClaudeHarnessAdapter
import CodexHarnessAdapter
import ClaudeTelemetryAdapter
import DarwinMetricsAdapter
import DiagnosticsAdapter
import FigCompletionAdapter
import FileSessionAdapter
import GhosttyAdapter
import ImageIOAdapter
import NeovimAdapter
import IPCAdapter
import OllamaAdapter
import OpenCodeHarnessAdapter
import ProjectContextAdapter
import UserNotificationsAdapter
import OSLog
import OTLPReceiverAdapter
import SmaltiCore
import SparkleUpdatesAdapter
import TOMLConfigAdapter

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "engine")
    private var runtime: GhosttyRuntime?
    /// F5: the one Appearance document every window's panel edits.
    private var appearance: AppearanceSession?
    /// F5 "Solo símbolo": a pane's prompt context for its header (from `RenderPrompt`).
    private var promptHeader: ((PaneID) -> String?)?
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
    private var configFile: URL?
    private var mainMenu: MainMenu?
    private let secureInput = SecureInput()
    private let diagnostics: any DiagnosticLog = OSLogDiagnostics(subsystem: AppIdentity.current.bundleIdentifier)
    /// ⌘+ ⌘− ⌘0 over `font_size`, for every pane of every window (F4.5).
    private var fontScale = FontScale(base: 13)
    private var stateDirectoryForTests: String?
    private var telemetry: UnixSocketTelemetry?
    private var observatory: ObservatoryRefresher?
    private var input: InputCoordinator?
    private var completionMenu: CompletionMenuController?
    private var historyPalette: HistoryPaletteController?
    private var transcripts: ClaudeTranscripts?
    private var harnesses = HarnessRegistry([])
    /// F6: claudecode.nvim is installed right now (`--ide` for the Claude sessions Smalti relaunches).
    private var connectsEditor: () -> Bool = { false }
    private var captures: HarnessCaptures?
    /// F7: Claude Code's telemetry from the panes, through the local OTLP receiver.
    private var claudeTelemetry: CollectTelemetry?
    /// F7: export and import of saved layouts as portable files.
    private var layoutSharing: LayoutSharing?
    private var reportedTelemetryFailure: String?
    /// F7.5: the commands the panes' agents wait to have approved, shared by every window.
    private var approvals: AgentApprovals?
    /// F7.6: the updater; nil in Smalti Dev unless a UI test passes `-SmaltiUpdateFeedURL`.
    private let updates = AppComposition.makeUpdates()
    private var approvalTimer: Timer?
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
            startUpdates()
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
        let store = TOMLConfigStore(config: settings.configFile, theme: settings.themeFile)
        let initial = ReloadConfig(store: store).execute()
        return Startup(
            settings: settings, store: store, initial: initial,
            theme: ThemeCatalog.apply(initial.config.appearance).theme)
    }

    /// F7.5 review 2: the guard's test flags exist only in Debug, so a persisted default never redirects the daily
    /// build's ⌘K rules or shortens its approvals.
    private static var debugGuardArgumentKeys: [String] {
        #if DEBUG
            LaunchSettings.guardArgumentKeys
        #else
            []
        #endif
    }

    /// `-Key value` launch arguments land in the argument domain of the user defaults.
    /// Claude Code's `CLAUDE_CONFIG_DIR` rides along in the same map (LaunchSettings keeps three parameters).
    private static func launchArguments() -> [String: String] {
        let keys =
            [
                LaunchSettings.configPathKey, LaunchSettings.shellCommandKey, LaunchSettings.statePathKey,
                LaunchSettings.claudeHomeKey, LaunchSettings.ollamaURLKey, LaunchSettings.userZdotdirKey,
            ] + LaunchSettings.harnessArgumentKeys + LaunchSettings.telemetryArgumentKeys
            + debugGuardArgumentKeys
        var arguments = keys.reduce(into: [String: String]()) { $0[$1] = UserDefaults.standard.string(forKey: $1) }
        let environment = ProcessInfo.processInfo.environment
        for key in [LaunchSettings.claudeConfigDirKey] + LaunchSettings.harnessEnvironmentKeys {
            arguments[key] = environment[key]
        }
        return arguments
    }

    /// F6: the first 2 MB of an edited file, to find the line of the change ("Editados por Claude").
    nonisolated private static func fileHead(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2 * 1024 * 1024)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// F6: Neovim sockets under a short owner-only folder (`sun_path` holds 104 bytes).
    private static func editorSocketDirectory(_ settings: LaunchSettings) -> String {
        EditorSocketDirectory.prepare(settings.editorSocketDirectory ?? "/private/tmp/smalti-\(getuid())")
    }

    /// F6: the four harnesses, each reading its own home as `LaunchSettings` resolved it.
    private static func harnessRegistry(_ settings: LaunchSettings) -> HarnessRegistry {
        HarnessRegistry([
            ClaudeHarness(projectsRoot: settings.claudeHome.appending(path: "projects")),
            CodexHarness(home: settings.codexHome),
            AntigravityHarness(root: settings.antigravityRoot),
            OpenCodeHarness(
                database: settings.opencodeDatabase
                    ?? OpenCodeHarness.defaultDatabase(dataHome: settings.opencodeDataHome)),
        ])
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

    private func startUpdates() {
        do {
            try updates?.start()
        } catch {
            logger.error("the updater did not start: \(String(describing: error), privacy: .public)")
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
            ipc: Self.ipcEndpoints(socket: socket, inputSocket: inputSocket), telemetry: startTelemetry(startup))
        harnesses = Self.harnessRegistry(startup.settings)
        layoutSharing = LayoutSharing(
            layouts: archive, files: SharedLayoutFiles(), harnesses: harnesses,
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
        let captures = HarnessCaptures(registry: harnesses)
        self.captures = captures
        // F6: `-SmaltiNvimConfigHome` in tests, never the user's `~/.config/nvim`.
        let claudecode = ClaudecodeNvimInstaller(configHome: startup.settings.nvimConfigHome)
        let editor = EditorSettings(
            editedFiles: TrackEditedFiles(readFile: Self.fileHead), nvim: startup.settings.nvimCommand,
            socketDirectory: Self.editorSocketDirectory(startup.settings), bridge: NeovimBridge(),
            connectsEditor: { claudecode.isInstalled })
        connectsEditor = editor.connectsEditor
        let dependencies = TilingController.Dependencies(
            engine: engine, configStore: startup.store, paneEnvironment: environment, transcripts: archive,
            namedLayouts: archive,
            harnesses: harnesses, captures: captures, editor: editor, updates: updates,
            agents: guardedAgents(
                Self.agentDependencies(notifier: makeNotifier(), claudecode: claudecode), startup: startup),
            home: try homeDirectory(),
            shellOverride: startup.settings.shellOverride,
            // A reload keeps the steps taken with ⌘+ and ⌘− on top of the new `font_size`.
            applyAppearance: { [weak self, weak runtime, weak engine] appearance throws(TerminalEngineError) in
                guard let self else { return }
                engine?.gridPadding = Point(x: appearance.paddingX, y: appearance.paddingY)
                fontScale = fontScale.rebased(appearance.fontSize)
                try runtime?.apply(appearance.withFontSize(fontScale.size))
            })
        fontScale = FontScale(base: startup.theme.terminal.fontSize)
        engine.gridPadding = Point(x: startup.theme.terminal.paddingX, y: startup.theme.terminal.paddingY)
        engine.reportsPointerWords = startup.initial.config.preview.hover
        controllerDependencies = dependencies
        configStore = startup.store
        configFile = startup.settings.configFile
        restorePreferences = archive
        startAppearance(startup)
        let (controller, visibility) = makeController(dependencies, initial: startup.initial)
        listenForAgents(on: socket, controller: controller)
        if let inputSocket { startInput(on: inputSocket, settings: inputSettings, startup: startup, engine: engine) }
        startObservatory(startup, controller: controller)
        let keeper = SessionKeeper(save: SaveSession(archive: archive, transcripts: archive, scrollback: engine))
        // The window in front at the time reports it: the first one may be closed by then.
        keeper.onFailure = { [weak self] reason in self?.controller?.report(.sessionSaveFailed(reason)) }
        keeper.editorPositions = { [weak self] in await self?.editorPositions() ?? [:] }
        self.runtime = runtime
        self.engine = engine
        sessionKeeper = keeper
        let composition = makeComposition(controller, visibility: visibility, engine: engine)
        installMenus(engine)
        // The receiver started before any window existed: its first status reaches the bar now.
        if let claudeTelemetry { telemetryChanged(claudeTelemetry) }
        switch LoadLastSession(archive: archive, preferences: archive).execute() {
        case .startFresh:
            controller.start()
        case .startFreshAfterUnreadable(let reason):
            controller.start()
            controller.report(.unreadableSession(reason))
        case .startFreshKeepingNewer(let version):
            controller.start()
            controller.report(.newerSession(version))
        case .restoreAll(let snapshot):
            let plans = WindowRestorePlan.make(from: snapshot, mode: .full, selection: .defaults(for: snapshot))
            restoreWindows(snapshot, plans: plans, into: composition)
        case .ask(let snapshot):
            // Asked where the first window was, so restoring does not move it under the user's eyes.
            if let frame = snapshot.windows.first?.frame { composition.place(at: frame) }
            composition.ask(snapshot, preferences: archive)
        }
        // While the resume screen asks, nothing is saved: quitting there keeps the last session.
        if !composition.isAskingToRestore { beginSaving(keepingPreviousSession: false) }
    }

    // MARK: - Appearance (F5)

    private func startAppearance(_ startup: Startup) {
        let session = AppearanceSession(
            config: startup.initial.config, themeFile: startup.settings.themeFile
        ) { [weak self] error in self?.controller?.report(.invalidConfig(error)) }
        session.onApply = { [weak self] document in self?.applyAppearance(document) }
        session.onRefresh = { [weak self] in self?.compositions.forEach { $0.refreshAppearancePanel() } }
        appearance = session
    }

    /// Every window paints the document; the engine (the app's) takes its terminal appearance once.
    private func applyAppearance(_ document: AppearanceDocument) {
        compositions.forEach { $0.controller.adopt(document) }
        compositions.first?.controller.applyEngineAppearance()
        input?.sendPromptStyle()
    }

    // MARK: - Windows (F4.5)

    /// A controller whose agents count as seen only while its own window is the key one, on screen.
    private func makeController(_ dependencies: TilingController.Dependencies, initial: ConfigReload)
        -> (TilingController, WindowVisibility)
    {
        let visibility = WindowVisibility()
        var agents = TilingController.AgentDependencies(
            notifier: dependencies.agents.notifier, integrations: dependencies.agents.integrations,
            isAppActive: { [weak visibility] in visibility?.isSeen ?? false })
        agents.guards = dependencies.agents.guards
        let controller = TilingController(dependencies.with(agents: agents), initial: initial)
        controller.promptHeader = { [weak self] pane in self?.promptHeader?(pane) }
        return (controller, visibility)
    }

    /// A window for `controller`, cascaded from the front one, in front. Its controller has not opened panes yet.
    @discardableResult
    private func makeComposition(
        _ controller: TilingController, visibility: WindowVisibility, engine: GhosttyTerminalEngine
    ) -> WindowComposition {
        let window = SmaltiWindow(theme: controller.theme)
        visibility.window = window
        if let front, let visible = (front.window.screen ?? NSScreen.main)?.visibleFrame {
            let next = WindowFrame.cascaded(
                from: front.windowedFrame, size: Size(width: window.frame.width, height: window.frame.height),
                visible: Rect(visible))
            window.setFrame(NSRect(next), display: false)
        }
        window.makeKeyAndOrderFront(nil)
        if let path = stateDirectoryForTests { window.setAccessibilityValue(path) }
        let composition = WindowComposition(window: window, controller: controller, services: windowServices(engine))
        compositions.append(composition)
        frontID = composition.id
        window.contentView?.layoutSubtreeIfNeeded()
        composition.controller.showSecureInput(secureInput.entry.isRequested)
        return composition
    }

    /// A new window with a fresh controller; nil before the engine exists.
    private func makeWindow() -> WindowComposition? {
        guard let dependencies = controllerDependencies, let store = configStore, let engine else { return nil }
        let (controller, visibility) = makeController(dependencies, initial: ReloadConfig(store: store).execute())
        // Block 4 review (M2): painted with the panel's document, also before theme.toml has it.
        if let document = appearance?.document { controller.adopt(document) }
        return makeComposition(controller, visibility: visibility, engine: engine)
    }

    /// Every window as the session sees it, the front one marked; nil with no windows.
    private func windowSet() -> WindowSet? {
        guard let first = compositions.first else { return nil }
        let set = compositions.dropFirst().reduce(WindowSet(first: first.state)) { $0.opening($1.state) }
        return set.bringingToFront(front?.id ?? first.id)
    }

    private func windowsChanged() {
        mainMenu?.refresh()
        guard let set = windowSet() else { return }
        sessionKeeper?.changed(set)
        let panes = Set(set.allPanes.map(\.id))
        input?.keepOnly(panes)
        // A closed pane's agent no longer waits for anyone (final review, M1); unchanged prompts send nothing.
        for composition in compositions {
            composition.controller.set.workspaces.forEach { input?.agentsChanged(in: $0.id) }
        }
        if secureInput.entry.isRequested {
            secureInput.keep(panes: panes)
            compositions.forEach { $0.controller.showSecureInput(secureInput.entry.isRequested) }
        }
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
        case .configReload:
            // The engine's appearance is the app's: one window applies it, the others follow the file.
            let isReloaded = compositions.first?.controller.reloadConfig() ?? false
            compositions.dropFirst().forEach { $0.controller.rereadConfig() }
            // Block 4 review (C1): only a reload that loaded replaces the panel's document.
            if isReloaded, let config = compositions.first?.controller.config {
                appearance?.reload(config)
                engine?.reportsPointerWords = config.preview.hover
                claudeTelemetry?.apply(config.extras)
                approvals?.settings = config.guards
                input?.sendPromptStyle()
            }
            mainMenu?.refresh()
        case .appAbout: showAbout()
        case .updatesCheck: updates.map { CheckForUpdates(updates: $0).execute() }
        case .updatesAutomatic:
            guard let updates else { return }
            composition.controller.report(
                StatusMessage(text: SetAutomaticUpdates(updates: updates).toggle(), isTransient: true))
            mainMenu?.refresh()
        case .helpDocs: URLOpener.open(SmaltiLinks.documentation)
        case .appSupport: URLOpener.open(SmaltiLinks.support)
        case .feedbackReport:
            composition.showFeedback(summary: Self.buildInfo.summary) { [weak self] kind, includesLogs in
                self?.report(kind, includingLogs: includesLogs)
            }
        case .logsShow: Task { await saveLogs() }
        case .fontIncrease: scaleFont(fontScale.increased())
        case .fontDecrease: scaleFont(fontScale.decreased())
        case .fontReset: scaleFont(fontScale.reset())
        case .configOpen: openConfig()
        case .appearanceOpen: appearance.map(composition.toggleAppearance)
        case .themeOpen: appearance?.openThemeFile()
        case .themeNext:
            let next = composition.controller.config.appearance.theme.next
            appearance?.selectTheme(next)
        case .ansiReset: appearance?.edit { $0.resetANSI() }
        case .legibilityToggle: appearance?.edit { $0.appearance.protectLegibility.toggle() }
        case .promptStudio: appearance.map(composition.toggleStudio)
        case .promptApply: composition.performInStudio(.apply)
        case .promptExport: composition.performInStudio(.export)
        case .secureInputToggle:
            secureInput.toggle()
            showSecureInput()
        case .layoutImport:
            layoutSharing?.importLayout(in: composition.window) { [weak composition] in
                composition?.controller.report($0)
            }
        default:
            if case .export(let name)? = command.namedLayout {
                layoutSharing?.export(name, from: composition.window) { [weak composition] in
                    composition?.controller.report($0)
                }
            }
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
        guard let engine else { return }
        let busy = RunningPrograms(engine: engine).busy(in: composition.controller.set.workspaces.flatMap(\.panes))
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
        composition.controller.forgetAllPanes()
        retainApprovals()
        composition.closeOverlays()
        // Block 4 review (I2): its Esc monitor and the color panel's target go with the window.
        composition.closeAppearancePanel()
        composition.closeStudio()
        composition.window.close()
        observatoryOpenChanged()
        frontID = set.frontID
        front?.window.makeKeyAndOrderFront(nil)
        windowsChanged()
    }

    /// ⌘J: the agent that has waited longest, in whichever window; that window comes to the front.
    private func jumpToWaitingAgent(from origin: WindowComposition) {
        guard let windows = windowSet(), let pane = AttentionQueue.panes(in: windows).first,
            let owner = composition(containing: pane), owner.controller.activate(pane)
        else {
            origin.controller.reportNobodyWaiting()
            return
        }
        owner.window.makeKeyAndOrderFront(nil)
    }

    /// Rebuilds the saved windows that have something chosen (`WindowRestorePlan`): the first into `first`, the
    /// rest into new ones, each at its saved frame refitted to the screens there are now. With nothing chosen,
    /// `first` starts fresh.
    private func restoreWindows(
        _ snapshot: SessionSnapshot, plans: [WindowRestorePlan], into first: WindowComposition
    ) {
        guard !plans.isEmpty else {
            first.controller.start()
            return
        }
        var inFront: WindowComposition?
        for (index, window) in plans.enumerated() {
            guard let composition = index == 0 ? first : makeWindow() else { continue }
            if let frame = window.saved.frame { composition.place(at: frame) }
            composition.controller.restore(window.plan, savedAt: snapshot.savedAt)
            if window.saved.isFullScreen { composition.window.toggleFullScreen(nil) }
            if window.isFront { inFront = composition }
        }
        inFront?.window.makeKeyAndOrderFront(nil)
    }

    /// What the user chose on "Retomar donde quedaste", in the window that asked.
    private func restoreChosen(_ choice: RestoreChoice, snapshot: SessionSnapshot, in asking: WindowComposition) {
        switch choice {
        case .restore(let selection):
            let plans = WindowRestorePlan.make(from: snapshot, mode: .full, selection: selection)
            restoreWindows(snapshot, plans: plans, into: asking)
        case .layoutsOnly:
            let plans = WindowRestorePlan.make(from: snapshot, mode: .layoutsOnly, selection: .defaults(for: snapshot))
            restoreWindows(snapshot, plans: plans, into: asking)
        case .startClean:
            asking.controller.start()
            beginSaving(keepingPreviousSession: true)
            return
        case .restoreAndOpen(let selection, let plan, let directory):
            // Nothing checked: the opened session is the first pane, with no empty shell next to it.
            if selection.checkedCount(in: snapshot) == 0 {
                if case .open = plan {
                    asking.controller.openHarnessSession(plan, directory: directory)
                    beginSaving(keepingPreviousSession: false)
                    return
                }
                asking.controller.start()
            } else {
                restoreWindows(
                    snapshot, plans: WindowRestorePlan.make(from: snapshot, mode: .full, selection: selection),
                    into: asking)
            }
            asking.controller.openHarnessSession(plan, directory: directory)
        }
        beginSaving(keepingPreviousSession: false)
    }

    // MARK: - Menus and app commands (F4.5)

    private func installMenus(_ engine: GhosttyTerminalEngine) {
        let menu = MainMenu(
            model: { [weak self] in self?.menuBar() ?? .empty },
            perform: { [weak self] command in self?.performFromMenu(command) })
        menu.install()
        mainMenu = menu
        engine.contextMenu = { [weak self] pane in self?.contextMenu(for: pane) }
        // F6: ⌘-click on a text file opens it in the window's Neovim.
        engine.commandClick = { [weak self] pane, word in
            guard let owner = self?.compositions.first(where: { $0.controller.pane(byID: pane) != nil }) else {
                return false
            }
            return owner.controller.editors.commandClick(on: word, in: pane)
        }
        // UI tests read the cell size to see ⌘+ and ⌘− take effect (F4.5 C9).
        engine.exposesCellSize = UserDefaults.standard.bool(forKey: "SmaltiExposeCellSize")
    }

    private func menuBar() -> MenuBar {
        guard let controller else { return .empty }
        var state = CatalogState(workspaces: controller.set, savedLayouts: controller.savedLayouts())
        state.updates = UpdatesAvailability(updates)
        let commands = CommandCatalog.commands(for: state, keymap: controller.config.keys, layouts: .standard)
        // The item shows the user's own choice; a password prompt turning it on is shown by the status bar.
        let checked: Set<CommandID> = secureInput.entry.isOnByUser ? [.secureInputToggle] : []
        return MenuModel.bar(
            keymap: controller.config.keys, commands: commands,
            state: MenuState(
                workspaces: controller.set, checked: checked, context: front?.menuContext ?? .unrestricted))
    }

    /// A menu item acts on the window in front; with none (all closed while quitting), only ⌘N makes sense.
    private func performFromMenu(_ command: CommandID) {
        // Another window is key ("Acerca de"): copy, paste, select all and close are its own.
        if let key = NSApp.keyWindow, !(key is SmaltiWindow), let standard = Self.standardActions[command] {
            NSApp.sendAction(standard, to: nil, from: nil)
            return
        }
        guard let front else {
            if command == .windowNew { openWindow(from: nil) }
            return
        }
        front.controller.perform(command)
    }

    private static let standardActions: [CommandID: Selector] = [
        .terminalCopy: #selector(NSText.copy(_:)), .terminalPaste: #selector(NSText.paste(_:)),
        .terminalSelectAll: #selector(NSResponder.selectAll(_:)), .paneClose: #selector(NSWindow.performClose(_:)),
        .windowClose: #selector(NSWindow.performClose(_:)),
    ]

    /// Right click on a pane: its window comes forward, the pane takes the focus, then the item runs.
    private func contextMenu(for pane: PaneID) -> NSMenu? {
        guard let owner = composition(containing: pane) else { return nil }
        let menu = NSMenu()
        let keymap = owner.controller.config.keys
        for item in MenuModel.contextMenu(keymap: keymap) {
            guard !item.isSeparator, let command = item.command else {
                menu.addItem(.separator())
                continue
            }
            let shortcut = item.chord.flatMap(KeyEquivalent.init)
            let nsItem = ClosureMenuItem(title: item.title, keyEquivalent: shortcut?.key ?? "") { [weak owner] in
                owner?.controller.focus(pane)
                owner?.controller.perform(command)
            }
            nsItem.keyEquivalentModifierMask = shortcut?.modifiers ?? []
            nsItem.allowsAutomaticKeyEquivalentLocalization = false
            menu.addItem(nsItem)
        }
        return menu
    }

    /// Every terminal at the new size; panes opened later get it too (the engine's config carries it).
    private func scaleFont(_ scale: FontScale) {
        guard scale != fontScale, let appearance = controller?.theme.terminal else { return }
        do {
            try runtime?.apply(appearance.withFontSize(scale.size))
            // Only a size that took effect becomes the one the next step starts from.
            fontScale = scale
        } catch {
            controller?.report(.engineFailure(error))
        }
    }

    /// A password prompt started or ended in `pane`: secure entry follows, and every status bar says so.
    private func secureInputRequested(_ isOn: Bool, in pane: PaneID) {
        secureInput.prompt(in: pane, isAsking: isOn)
        showSecureInput()
    }

    private func showSecureInput() {
        compositions.forEach { $0.controller.showSecureInput(secureInput.entry.isRequested) }
        mainMenu?.refresh()
    }

    // MARK: - Feedback and logs (F4.5)

    /// What a report says about this build and this Mac.
    private static var buildInfo: BuildInfo {
        let commit = Bundle.main.infoDictionary?["SmaltiGitCommit"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return BuildInfo(
            version: version, commit: commit, macOS: "\(system.majorVersion).\(system.minorVersion)", chip: chipName)
    }

    /// "Apple M4", from the kernel; "Apple silicon" when it cannot be read.
    private static var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple silicon" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "Apple silicon" }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }

    /// Saves the logs first when asked, then opens the prefilled issue: the user reads it and submits it.
    private func report(_ kind: FeedbackKind, includingLogs: Bool) {
        Task {
            if includingLogs { await saveLogs() }
            URLOpener.open(FeedbackReport.issueURL(kind: kind, build: Self.buildInfo))
        }
    }

    /// "Mostrar registros…": this run's logs in Downloads (`-SmaltiDownloadsPath` in tests), shown in Finder.
    private func saveLogs() async {
        let stamp = Date.now.formatted(
            .verbatim(
                "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: .current, calendar: .current))
        let file = Self.downloads.appending(path: "smalti-registros-\(stamp).log")
        do {
            try await diagnostics.export(to: file, heading: Self.buildInfo.summary)
            URLOpener.reveal(file)
        } catch {
            logger.error("could not save the logs: \(String(describing: error), privacy: .public)")
            controller?.report(.logsFailed(file.path(percentEncoded: false)))
        }
    }

    private static var downloads: URL {
        if let path = UserDefaults.standard.string(forKey: "SmaltiDownloadsPath"), !path.isEmpty {
            return URL(filePath: path)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }

    /// "Acerca de Smalti": the standard panel with the version, the commit, the credits and (F7.6) the links to the
    /// documentation, to support Smalti and to the third-party notices inside the bundle.
    private func showAbout() {
        let build = Self.buildInfo
        let ghostty = Bundle.main.infoDictionary?["SmaltiGhosttyVersion"] as? String ?? "?"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(build.version) (\(build.commit))", .version: "",
            .credits: AboutCredits.text(ghosttyVersion: ghostty, notices: Self.noticesFile),
        ])
        NSApp.activate()
    }

    private static var noticesFile: URL? {
        Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
    }

    /// F7.6: Release builds read `SUFeedURL`; Debug ones have none and update only in UI tests, with a local feed.
    private static func makeUpdates() -> SparkleUpdates? {
        #if DEBUG
            let override = UserDefaults.standard.string(forKey: updateFeedKey).flatMap(URL.init(string:))
        #else
            let override: URL? = nil
        #endif
        return SparkleUpdates.make(bundle: .main, feedOverride: override)
    }

    /// `-SmaltiUpdateFeedURL <url>` (Debug, UI tests): the feed Smalti Dev checks.
    static let updateFeedKey = "SmaltiUpdateFeedURL"

    /// ⌘,: the TOML in the user's editor; written first from the commented template when there is none.
    private func openConfig() {
        guard let file = configFile else { return }
        let path = file.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ConfigTemplate.text(defaults: .defaults).write(to: file, atomically: true, encoding: .utf8)
            } catch {
                logger.error("could not write the config template: \(String(describing: error), privacy: .public)")
                controller?.report(.configTemplateFailed(path))
                return
            }
        }
        URLOpener.open(file)
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
            makeSessionSearch: { [harnesses, connectsEditor] in
                SessionSearchModel(registry: harnesses, connectsEditor: connectsEditor)
            },
            changed: { [weak self] in self?.windowsChanged() },
            restoreChosen: { [weak self] choice, snapshot, asking in
                self?.restoreChosen(choice, snapshot: snapshot, in: asking)
            },
            appCommand: { [weak self] command, composition in self?.perform(command, from: composition) },
            becameFront: { [weak self] composition in
                self?.frontID = composition.id
                self?.mainMenu?.refresh()
            },
            completionMenu: { [weak self] in self?.completionMenu },
            historyPalette: { [weak self] in self?.historyPalette },
            openHistory: { [weak self] pane in self?.input?.openHistory(for: pane) },
            observatoryOpenChanged: { [weak self] in self?.observatoryOpenChanged() },
            secureInputRequested: { [weak self] isOn, pane in self?.secureInputRequested(isOn, in: pane) },
            imageFiles: ImageIOImageFiles(),
            lastCommand: { [weak self] pane in await self?.input?.lastCommand(in: pane) })
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
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
            usage: [
                OpenCodeUsage(
                    database: settings.opencodeDatabase
                        ?? OpenCodeHarness.defaultDatabase(dataHome: settings.opencodeDataHome))
            ])
        let refresher = ObservatoryRefresher(
            observe: ObserveAgents(sources),
            callbacks: .init(
                panes: { [weak self] in self?.compositions.flatMap { PaneAgent.all(in: $0.controller.set) } ?? [] },
                onSnapshot: { [weak self] frame in self?.compositions.forEach { $0.show(frame) } },
                onError: { [weak self] in self?.controller?.report(.transcriptsUnreadable($0)) },
                telemetry: { [weak self] in
                    (self?.claudeTelemetry?.ledger ?? TelemetryLedger(), self?.claudeTelemetry?.status ?? .off)
                }))
        refresher.start()
        observatory = refresher
    }

    // MARK: - Telemetry (F7)

    /// Starts the receiver before the first pane opens, so every pane gets the variables from the start.
    private func startTelemetry(_ startup: Startup) -> CollectTelemetry {
        let settings = startup.settings
        let collector = CollectTelemetry(
            receiver: LoopbackOTLPReceiver(),
            settings: ClaudeSettingsTelemetryCheck(
                claudeHome: settings.claudeHome,
                managedSettings: settings.managedSettings ?? ClaudeSettingsTelemetryCheck.defaultManagedSettings))
        collector.onChange = { [weak self, weak collector] in
            guard let self, let collector else { return }
            telemetryChanged(collector)
        }
        collector.apply(startup.initial.config.extras)
        claudeTelemetry = collector
        telemetryProbe = settings.telemetryProbe
        return collector
    }

    private var telemetryProbe: URL?

    private func telemetryChanged(_ collector: CollectTelemetry) {
        observatory?.telemetryChanged()
        writeTelemetryProbe(collector.status)
        guard case .failed(let reason) = collector.status else {
            reportedTelemetryFailure = nil
            return
        }
        // Once per failure: a later reload that fails the same way does not repeat it.
        guard reportedTelemetryFailure != reason, let controller else { return }
        reportedTelemetryFailure = reason
        controller.report(.telemetryReceiverFailed(reason))
    }

    /// `-SmaltiTelemetryProbe <file>` (tests): the receiver's status and port, rewritten on every change.
    private func writeTelemetryProbe(_ status: TelemetryStatus) {
        guard let telemetryProbe else { return }
        let fields: [String: Any] =
            switch status {
            case .off: ["status": "off"]
            case .configuredByUser: ["status": "configuredByUser"]
            case .listening(let endpoint): ["status": "listening", "port": Int(endpoint.port)]
            case .failed(let reason): ["status": "failed", "reason": reason]
            }
        do {
            try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]).write(
                to: telemetryProbe, options: .atomic)
        } catch {
            logger.error("telemetry probe not written: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Stops the receiver before the app quits.
    func stopTelemetry() {
        claudeTelemetry?.apply(ExtrasSettings(otlp: false))
    }

    /// Hooks reach the app through `<state>/smalti.sock`. If another instance of this build owns it, this one runs
    /// without agent states and says so.
    private func listenForAgents(on socket: URL, controller: TilingController) {
        do {
            let telemetry = try UnixSocketTelemetry(socketFile: socket, clock: { .now })
            self.telemetry = telemetry
            let events = telemetry.events()
            let requests = telemetry.requests()
            Task { [weak self] in
                for await request in requests { self?.approvals?.receive(request) }
            }
            // Final review: a hook Claude cancelled takes its card away.
            let cancellations = telemetry.cancellations()
            Task { [weak self] in
                for await id in cancellations { self?.approvals?.cancel(id) }
            }
            Task { [weak self] in
                for await event in events {
                    // The window that holds the pane applies it; the others ignore a pane they do not have.
                    self?.compositions.forEach { $0.controller.handle(event) }
                    self?.observatory?.agentEvent(event)
                    // F5 "Agentes que esperan": the quiet prompts of the workspace show it without a keypress.
                    if let workspace = self?.workspace(containing: event.pane)?.id {
                        self?.input?.agentsChanged(in: workspace)
                    }
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
        let specs = FigSpecs(
            user: startup.settings.configFile.deletingLastPathComponent().appending(path: "completions"),
            runner: GeneratorRunner(timeout: settings.generatorTimeout))
        let ports = InputSession.Ports(
            history: FileCommandHistory(
                file: state.appending(path: "input/history.jsonl"), limit: settings.historyLimit),
            project: FileProjectContext(), completions: specs, predictor: HeuristicPredictor())
        let session = InputSession(ports: ports, settings: settings, clock: { .now })
        let coordinator = InputCoordinator(session: session, provider: engine) { [weak self] pane in
            self?.composition(containing: pane)?.controller.set.workspaces.lazy.flatMap(\.panes)
                .first { $0.id == pane }?.workingDirectory.path
        }
        // F5.6: the same specs as completion, so a spec loaded for Tab colors subcommands too.
        coordinator.highlighter = HighlightLine(paths: FileSystemPathFacts(), completions: specs)
        coordinator.isHighlighting = { [weak self] in
            Self.isHighlighting(self?.controller?.config ?? startup.initial.config)
        }
        connectPrompt(coordinator, startup: startup)
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
                    returnFocus: { [weak self] pane in self?.composition(containing: pane)?.focusKeyboard(on: pane) }
                ))
        } catch {
            logger.error("input socket unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// F5: zsh's `context` → `RenderPrompt` → `prompt`; agents that start waiting re-send it; "Solo símbolo" moves
    /// the context to the pane header.
    private func connectPrompt(_ coordinator: InputCoordinator, startup: Startup) {
        let environment = PromptEnvironment(
            settings: { [weak self] in
                let config = self?.controller?.config ?? startup.initial.config
                return (config.prompt, ThemeCatalog.apply(config.appearance))
            },
            agents: { [weak self] pane in
                self?.workspace(containing: pane)?.waitingAgents(besides: pane) ?? WaitingAgents()
            },
            workspace: { [weak self] pane in self?.workspace(containing: pane)?.id },
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false), now: { Date() },
            highlighting: { [weak self] in Self.isHighlighting(self?.controller?.config ?? startup.initial.config) })
        let render = RenderPrompt(facts: FilePromptFacts(), environment: environment)
        coordinator.renderPrompt = render
        // Only a header that shows the prompt's context changes with it (block 5 review, M2).
        var headers: [PaneID: String] = [:]
        coordinator.onPromptRendered = { [weak self] pane in
            let header = render.headerText(for: pane)
            guard header != headers[pane] else { return }
            headers[pane] = header
            self?.composition(containing: pane)?.controller.refresh()
        }
        promptHeader = { pane in render.headerText(for: pane) }
    }

    /// F5.6: `[input] highlighting`, only while the input channel itself is on.
    private static func isHighlighting(_ config: SmaltiConfig) -> Bool {
        config.input.isEnabled && config.input.isHighlighting
    }

    private func workspace(containing pane: PaneID) -> Workspace? {
        composition(containing: pane)?.controller.set.workspaces.first { $0.panes.contains { $0.id == pane } }
    }

    private static func ipcEndpoints(socket: URL, inputSocket: URL?) -> IPCEndpoints? {
        guard let cli = Bundle.main.resourceURL?.appending(path: "bin/smalti"),
            FileManager.default.isExecutableFile(atPath: cli.path(percentEncoded: false))
        else { return nil }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return IPCEndpoints(socket: socket, cli: cli, inheritedPath: path, inputSocket: inputSocket)
    }

    // MARK: - Agent guards (F7.5)

    /// The agents' dependencies plus the approvals: one queue for the app, its timer, and what ⌘K lists.
    private func guardedAgents(_ base: TilingController.AgentDependencies, startup: Startup)
        -> TilingController.AgentDependencies
    {
        let approvals = AgentApprovals(
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
            timeout: startup.settings.approvalTimeout)
        approvals.settings = startup.initial.config.guards
        approvals.onChange = { [weak self] change in self?.approvalChanged(change) }
        self.approvals = approvals
        var agents = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let fixedRoot = startup.settings.projectPermissionsRoot
        agents.guards = TilingController.GuardDependencies(
            approvals: approvals, entries: { [weak self] in self?.approvalEntries() ?? [] },
            panesChanged: { [weak self] in self?.retainApprovals() },
            secrets: ProtectProjectSecrets(permissions: ClaudeProjectPermissions(), home: home),
            projectRoot: { directory in fixedRoot ?? ClaudeProjectPermissions.projectRoot(containing: directory) })
        return agents
    }

    private func approvalChanged(_ change: AgentApprovalChange) {
        compositions.forEach { $0.controller.handleApproval(change) }
        scheduleApprovalExpiry()
    }

    /// One timer, for the nearest deadline.
    private func scheduleApprovalExpiry() {
        approvalTimer?.invalidate()
        approvalTimer = nil
        guard let deadline = approvals?.nextDeadline else { return }
        // Review 2: in the common modes (an open menu or a live resize does not hold it), and rescheduled after every
        // firing, even when the clock went back and nothing expired.
        let timer = Timer(timeInterval: max(0, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.approvals?.expire(now: Date())
                self?.scheduleApprovalExpiry()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        approvalTimer = timer
    }

    /// The waiting commands of every window, oldest first, with their workspace's name.
    private func approvalEntries() -> [ApprovalEntry] {
        (approvals?.allPending ?? []).compactMap { approval in
            let set = composition(containing: approval.pane)?.controller.set
            let workspace = set?.workspace(containing: approval.pane).flatMap { id in
                set?.workspaces.first { $0.id == id }?.name
            }
            return workspace.map { ApprovalEntry(approval: approval, workspace: $0) }
        }
    }

    /// Requests of panes no window has any more are denied.
    private func retainApprovals() {
        let panes = compositions.flatMap { $0.controller.set.workspaces.flatMap(\.panes).map(\.id) }
        approvals?.retain(Set(panes))
    }

    /// The Claude integration and its state, asked once at launch (F5.6).
    private static func agentDependencies(notifier: any Notifier, claudecode: ClaudecodeNvimInstaller)
        -> TilingController.AgentDependencies
    {
        let integrations: [IntegrationID: ClaudeIntegrationStatus] = [
            .claudePlugin: ClaudeIntegrationStatus(integration: claudeIntegration()),
            .claudecodeNvim: ClaudeIntegrationStatus(integration: claudecode),
        ]
        integrations.values.forEach { $0.refresh(forced: true) }
        return TilingController.AgentDependencies(
            notifier: notifier, integrations: integrations,
            // Replaced per window in `makeController`: "visible" is that window's, not the app's.
            isAppActive: { NSApp.isActive })
    }

    /// `claude` is wherever the user's interactive zsh puts it; `SMALTI=1` keeps that shell out of tmux. UI tests
    /// pass a fake one with `-SmaltiClaudeCommand` (F5.6), so the real `~/.claude` is never touched.
    private static func claudeIntegration() -> ClaudePluginInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let source = Bundle.main.resourceURL?.appending(path: "claude-plugin") ?? home
        let environment = ProcessInfo.processInfo.environment.merging(["SMALTI": "1"]) { _, smalti in smalti }
        // UI tests: a fake `claude` run by a shell without startup files, never the user's login shell (F5.6).
        let fake = UserDefaults.standard.string(forKey: "SmaltiClaudeCommand")
        // Shared by both builds on purpose; an isolated launch (`-SmaltiStatePath`, UI tests) keeps it in its own
        // state, so installing from a test never rewrites the daily Smalti's copy (F5.6).
        let shared = home.appending(path: "Library/Application Support/Smalti")
        let state = UserDefaults.standard.string(forKey: "SmaltiStatePath").map { URL(filePath: $0) } ?? shared
        return ClaudePluginInstaller(
            pluginSource: source, installDirectory: state.appending(path: "claude-plugin"),
            runner: ShellCommandRunner(
                shell: fake == nil ? ["/bin/zsh", "-lic"] : ["/bin/zsh", "-fc"], environment: environment),
            command: fake.map { ["/bin/sh", $0] } ?? ["claude"])
    }

    /// The observatory refreshes fast while any window shows it.
    private func observatoryOpenChanged() {
        observatory?.isObservatoryOpen = compositions.contains(where: \.isObservatoryOpen)
    }

    private var isConfirmingQuit = false

    /// ⌘Q: asks in the front window when something runs in any window or workspace; `answer` gets the choice (true
    /// at once when nothing runs). The app comes forward first (hidden, minimized, or quitting from the Dock or a
    /// logout) so the question is never asked out of sight; a repeated ⌘Q while it asks adds no second question.
    func confirmQuit(_ answer: @escaping (Bool) -> Void) {
        guard let windows = windowSet(), let front, let settings = controller?.config.window else {
            answer(true)
            return
        }
        guard !isConfirmingQuit else {
            answer(false)
            return
        }
        let busy = engine.map { RunningPrograms(engine: $0).busy(in: windows) } ?? CloseGuard.busyPanes(in: windows)
        let count = CloseGuard.windowsWithBusyPanes(busy, in: windows)
        guard let question = CloseGuard.question(for: .quit(windowCount: count), busy: busy, settings: settings) else {
            answer(true)
            return
        }
        isConfirmingQuit = true
        NSApp.unhide(nil)
        NSApp.activate()
        if front.window.isMiniaturized { front.window.deminiaturize(nil) }
        front.window.makeKeyAndOrderFront(nil)
        CloseConfirmation.ask(question, in: front.window) { [weak self] confirmed in
            self?.isConfirmingQuit = false
            answer(confirmed)
        }
    }

    /// `applicationShouldTerminate`: saves everything, scrollback included, before the app quits.
    /// F6: every window's Smalti Neovims, for the session.
    private func editorPositions() async -> [PaneID: EditorPosition] {
        var all: [PaneID: EditorPosition] = [:]
        for composition in compositions {
            all.merge(await composition.controller.editors.positions()) { first, _ in first }
        }
        return all
    }

    func saveForQuit() async {
        // F7.5: every waiting command is denied before the socket closes; nobody would approve it.
        approvals?.stop()
        // Block 4 review (I1): an Appearance change of the last 300 ms is written before quitting.
        appearance?.saveIfPending()
        secureInput.releaseAll()
        windowsChanged()
        await sessionKeeper?.saveForQuit()
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
