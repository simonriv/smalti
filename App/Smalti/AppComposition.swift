import AppKit
import ClaudeHarnessAdapter
import ClaudeTelemetryAdapter
import DarwinMetricsAdapter
import DiagnosticsAdapter
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
    /// F5: the one Appearance document every window's panel edits.
    private var appearance: AppearanceSession?
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
        let store = TOMLConfigStore(config: settings.configFile, theme: settings.themeFile)
        let initial = ReloadConfig(store: store).execute()
        return Startup(
            settings: settings, store: store, initial: initial,
            theme: ThemeCatalog.apply(initial.config.appearance).theme)
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
                // Replaced per window in `makeController`: "visible" is that window's, not the app's.
                isAppActive: { NSApp.isActive }),
            home: try homeDirectory(),
            shellOverride: startup.settings.shellOverride,
            // A reload keeps the steps taken with ⌘+ and ⌘− on top of the new `font_size`.
            applyAppearance: { [weak self, weak runtime] appearance throws(TerminalEngineError) in
                guard let self else { return }
                fontScale = fontScale.rebased(appearance.fontSize)
                try runtime?.apply(appearance.withFontSize(fontScale.size))
            })
        fontScale = FontScale(base: startup.theme.terminal.fontSize)
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
        self.runtime = runtime
        self.engine = engine
        sessionKeeper = keeper
        let composition = makeComposition(controller, visibility: visibility, engine: engine)
        installMenus(engine)
        switch LoadLastSession(archive: archive, preferences: archive).execute() {
        case .startFresh:
            controller.start()
        case .startFreshAfterUnreadable(let reason):
            controller.start()
            controller.report(.unreadableSession(reason))
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
    }

    // MARK: - Windows (F4.5)

    /// A controller whose agents count as seen only while its own window is the key one, on screen.
    private func makeController(_ dependencies: TilingController.Dependencies, initial: ConfigReload)
        -> (TilingController, WindowVisibility)
    {
        let visibility = WindowVisibility()
        let agents = TilingController.AgentDependencies(
            notifier: dependencies.agents.notifier, integration: dependencies.agents.integration,
            isAppActive: { [weak visibility] in visibility?.isSeen ?? false })
        return (TilingController(dependencies.with(agents: agents), initial: initial), visibility)
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
            if isReloaded, let config = compositions.first?.controller.config { appearance?.reload(config) }
            mainMenu?.refresh()
        case .appAbout: showAbout()
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
        case .secureInputToggle:
            secureInput.toggle()
            showSecureInput()
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
        composition.closeOverlays()
        // Block 4 review (I2): its Esc monitor and the color panel's target go with the window.
        composition.closeAppearancePanel()
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
        // UI tests read the cell size to see ⌘+ and ⌘− take effect (F4.5 C9).
        engine.exposesCellSize = UserDefaults.standard.bool(forKey: "SmaltiExposeCellSize")
    }

    private func menuBar() -> MenuBar {
        guard let controller else { return .empty }
        let commands = CommandCatalog.commands(
            for: controller.set, keymap: controller.config.keys, layouts: .standard,
            savedLayouts: controller.savedLayouts())
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

    /// "Acerca de Smalti": the standard panel with the version, the commit and the credits.
    private func showAbout() {
        let build = Self.buildInfo
        let ghostty = Bundle.main.infoDictionary?["SmaltiGhosttyVersion"] as? String ?? "?"
        let credits = NSAttributedString(
            string: "libghostty \(ghostty) (MIT) · Inter (OFL) · JetBrains Mono (OFL) · specs de Fig (ISC)",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(build.version) (\(build.commit))", .version: "", .credits: credits,
        ])
        NSApp.activate()
    }

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
            secureInputRequested: { [weak self] isOn, pane in self?.secureInputRequested(isOn, in: pane) })
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
                onError: { [weak self] in self?.controller?.report(.transcriptsUnreadable($0)) }))
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
                    returnFocus: { [weak self] pane in self?.composition(containing: pane)?.focusKeyboard(on: pane) }
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
    func saveForQuit() {
        // Block 4 review (I1): an Appearance change of the last 300 ms is written before quitting.
        appearance?.saveIfPending()
        secureInput.releaseAll()
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
