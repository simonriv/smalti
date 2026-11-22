import AppKit
import GhosttyAdapter
import OSLog
import SmaltiCore
import TOMLConfigAdapter

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let logger = Logger(subsystem: "dev.simonriv.smalti", category: "engine")
    private var window: SmaltiWindow?
    private var runtime: GhosttyRuntime?
    private var engine: GhosttyTerminalEngine?
    private var controller: TilingController?
    private var palette: CommandPaletteController?

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
        WindowGlass.apply(blurRadius: startup.theme.window.blurRadius, to: window)
        self.window = window
        do {
            try start(startup, in: window)
        } catch {
            fail(error)
        }
    }

    private static func readStartup() -> Startup {
        let settings = LaunchSettings(
            arguments: launchArguments(), home: FileManager.default.homeDirectoryForCurrentUser)
        let store = TOMLConfigStore(file: settings.configFile)
        let initial = ReloadConfig(store: store).execute()
        return Startup(
            settings: settings, store: store, initial: initial,
            theme: Theme.obsidian.applying(initial.config.appearance))
    }

    /// `-Key value` launch arguments land in the argument domain of the user defaults.
    private static func launchArguments() -> [String: String] {
        let keys = [LaunchSettings.configPathKey, LaunchSettings.shellCommandKey]
        return keys.reduce(into: [:]) { arguments, key in arguments[key] = UserDefaults.standard.string(forKey: key) }
    }

    private func start(_ startup: Startup, in window: SmaltiWindow) throws(TerminalEngineError) {
        let runtime = try makeRuntime(startup.theme.terminal)
        let engine = GhosttyTerminalEngine(runtime: runtime)
        let controller = TilingController(
            .init(
                engine: engine, configStore: startup.store, version: Self.version, home: try homeDirectory(),
                shellOverride: startup.settings.shellOverride,
                applyAppearance: { [weak runtime] appearance throws(TerminalEngineError) in
                    try runtime?.apply(appearance)
                }),
            initial: startup.initial)
        connect(controller, to: window, engine: engine)
        self.runtime = runtime
        self.engine = engine
        self.controller = controller
        window.contentView?.layoutSubtreeIfNeeded()
        controller.start()
    }

    private func connect(_ controller: TilingController, to window: SmaltiWindow, engine: GhosttyTerminalEngine) {
        let grid = window.paneGrid
        controller.area = { [weak grid] in grid?.area ?? .zero }
        controller.onChange = { [weak self, weak window] state in
            window?.strip.render(state)
            window?.paneGrid.render(state) { engine.view(for: $0) }
            window?.statusBar.render(state)
            self?.focusKeyboard(on: state.set.active.focusedPane)
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
                        query, set: controller.set, keymap: controller.config.keys)
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
        window.routeKey = { router.route($0, composing: $1) }
    }

    /// Keystrokes go to the focused pane's terminal.
    private func focusKeyboard(on pane: PaneID?) {
        guard palette?.isOpen != true, let window, let pane, let view = engine?.view(for: pane),
            window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)
    }

    private func makeRuntime(_ appearance: TerminalAppearance) throws(TerminalEngineError) -> GhosttyRuntime {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: Bundle.main.resourceURL?.appending(path: "ghostty"))
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(appearance), writingTo: Self.engineConfigFile)
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

    private static var engineConfigFile: URL {
        URL.applicationSupportDirectory.appending(path: "Smalti/ghostty.conf")
    }
}
