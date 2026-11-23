import AppKit
import GhosttyAdapter
import SmaltiCore

/// What a window needs from the app's shared services. The app builds it once; every window gets the same one.
@MainActor
struct WindowServices {
    let engine: GhosttyTerminalEngine
    let harnesses: HarnessRegistry
    /// The window's workspaces changed: the session keeper and the input coordinator follow.
    let workspacesChanged: (WorkspaceSet) -> Void
    /// The user chose on the resume screen; `keepingPreviousSession` is "Empezar de cero".
    let restoreFinished: (_ set: WorkspaceSet, _ keepingPreviousSession: Bool) -> Void
    /// The Tab menu and the ⌃R palette are the app's (one input coordinator for every pane).
    let completionMenu: () -> CompletionMenuController?
    let historyPalette: () -> HistoryPaletteController?
    let openHistory: (PaneID) -> Void
    let observatoryOpenChanged: (Bool) -> Void
}

/// One window and everything drawn in it: its tiling controller, palette, observatory overlay, resume screen and
/// keyboard routing. Only `AppComposition` creates it; it builds no infrastructure.
@MainActor
final class WindowComposition {
    let window: SmaltiWindow
    let controller: TilingController
    private let services: WindowServices
    private var palette: CommandPaletteController?
    private var observatoryScreen: ObservatoryController?
    private var restoreScreen: RestoreController?
    /// What the glass was last painted with, so a publish that does not change it repaints nothing.
    private var appliedWindowTokens: WindowTokens?

    init(window: SmaltiWindow, controller: TilingController, services: WindowServices) {
        self.window = window
        self.controller = controller
        self.services = services
        applyGlass(controller.theme)
        connect()
    }

    var isAskingToRestore: Bool { restoreScreen != nil }

    /// A palette, the observatory or the ⌃R palette owns the keyboard.
    var hasOverlayOpen: Bool {
        palette?.isOpen == true || observatoryScreen?.isOpen == true || services.historyPalette()?.isOpen == true
    }

    func dismissObservatory() {
        observatoryScreen?.dismiss()
    }

    func show(_ frame: ObservatoryFrame) {
        controller.show(frame)
        observatoryScreen?.show(frame.snapshot)
    }

    // MARK: - Resume screen

    /// "Retomar donde quedaste": shown instead of the strip and the panes until the user chooses.
    func ask(_ snapshot: SessionSnapshot, preferences: any RestorePreferenceStore) {
        guard let content = window.contentView else {
            // Without a place to ask, restore what the defaults would: never start empty over a saved session.
            controller.restore(snapshot, mode: .full, selection: .defaults(for: snapshot))
            return
        }
        let listing = RestoreController.Content(
            snapshot: snapshot,
            workspaces: ResumeListing.workspaces(in: snapshot, home: controller.home, harnesses: services.harnesses),
            closedAt: ClosedAtPhrase.text(closedAt: snapshot.savedAt, now: .now, calendar: .current))
        let screen = RestoreController(listing, theme: controller.theme, preferences: preferences) {
            [weak self] choice in self?.finishAsking(choice, snapshot: snapshot)
        }
        screen.view.frame = content.bounds
        screen.view.autoresizingMask = [.width, .height]
        content.addSubview(screen.view)
        setTilingHidden(true)
        window.makeFirstResponder(screen.view)
        restoreScreen = screen
    }

    private func finishAsking(_ choice: RestoreChoice, snapshot: SessionSnapshot) {
        restoreScreen?.view.removeFromSuperview()
        restoreScreen = nil
        setTilingHidden(false)
        switch choice {
        case .restore(let selection): controller.restore(snapshot, mode: .full, selection: selection)
        case .layoutsOnly: controller.restore(snapshot, mode: .layoutsOnly, selection: .defaults(for: snapshot))
        case .startClean:
            controller.start()
            services.restoreFinished(controller.set, true)
            return
        }
        services.restoreFinished(controller.set, false)
    }

    private func setTilingHidden(_ hidden: Bool) {
        [window.strip, window.paneGrid, window.statusBar].forEach { $0.isHidden = hidden }
    }

    // MARK: - Wiring

    private func connect() {
        let grid = window.paneGrid
        let engine = services.engine
        controller.area = { [weak grid] in grid?.area ?? .zero }
        controller.onChange = { [weak self] state in
            guard let self else { return }
            applyGlass(state.theme)
            window.strip.render(state)
            window.paneGrid.render(state) { engine.view(for: $0) }
            window.statusBar.render(state)
            focusKeyboard(on: state.set.active.focusedPane)
            services.workspacesChanged(state.set)
        }
        controller.onObservatoryChange = { [weak self] state in
            guard let self else { return }
            window.paneGrid.render(state) { engine.view(for: $0) }
            window.statusBar.render(state)
        }
        grid.onPaneClicked = { [weak controller] pane in controller?.focus(pane) }
        window.strip.onCommand = { [weak controller] command in controller?.perform(command) }
        connectPalette()
        connectKeyboard()
    }

    /// ⌘K and "Renombrar workspace…" open the palette; while it is open the panes dim and keep their processes.
    private func connectPalette() {
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
        palette.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
            // An overlay over the Tab menu takes the keyboard: the menu goes away rather than answer its keys.
            if isOpen { services.completionMenu()?.close() }
        }
        let screen = makeObservatoryScreen()
        observatoryScreen = screen
        controller.onViewCommand = { [weak self, weak palette, weak screen] command in
            guard let self, let palette else { return }
            let theme = controller.theme
            switch command {
            case .workspaceRename: palette.beginRename(theme: theme)
            case .observatoryToggle: screen?.toggle(theme: theme)
            case .observatoryPeriod: screen?.cyclePeriod()
            case .historySearch:
                if let pane = controller.set.active.focusedPane { services.openHistory(pane) }
            default: palette.toggle(theme: theme)
            }
        }
        self.palette = palette
    }

    /// ⌘⇧A: the observatory over the window; the panes stay alive and get the focus back when it closes.
    private func makeObservatoryScreen() -> ObservatoryController {
        ObservatoryController(
            window: window,
            actions: .init(
                setTilingHidden: { [weak self] hidden in self?.setTilingHidden(hidden) },
                didClose: { [weak self] pane in
                    guard let self else { return }
                    // A pane that closed meanwhile cannot be activated: the focused one gets the keyboard back.
                    if pane.map(controller.activate) != true {
                        focusKeyboard(on: controller.set.active.focusedPane)
                    }
                },
                openChanged: { [weak self] isOpen in
                    self?.services.observatoryOpenChanged(isOpen)
                    if isOpen { self?.services.completionMenu()?.close() }
                }))
    }

    private func connectKeyboard() {
        let router = KeyRouter(
            keymap: { [weak controller] in controller?.config.keys ?? .standard },
            context: { [weak self] in self?.keyContext ?? .unrestricted },
            perform: { [weak controller] command in controller?.perform(command) })
        // The resume screen owns the keyboard: no tiling shortcut acts, and its own keys reach it untouched.
        window.routeKey = { [weak self] event, composing in
            guard let self, restoreScreen == nil else { return false }
            if !composing, services.completionMenu()?.handle(event) == true { return true }
            if services.historyPalette()?.handle(event) == true { return true }
            return router.route(event, composing: composing)
        }
    }

    /// An open palette lets only ⌘K through; an open observatory only ⌘⇧A and ⌘P (its own keys reach its view); ⌘P
    /// reaches the terminal while the observatory is closed.
    private var keyContext: KeyContext {
        if palette?.isOpen == true { return .overlay(allowing: [.paletteOpen]) }
        // The ⌃R palette owns the keyboard: no tiling shortcut acts while it is open.
        if services.historyPalette()?.isOpen == true { return .overlay(allowing: []) }
        if observatoryScreen?.isOpen == true { return KeyContext(allowing: [.observatoryToggle, .observatoryPeriod]) }
        return KeyContext(passingThrough: [.observatoryPeriod])
    }

    /// At startup and whenever "Recargar configuración" changes `glass_opacity` or `blur`.
    private func applyGlass(_ theme: Theme) {
        guard theme.window != appliedWindowTokens else { return }
        window.applyGlass(theme)
        appliedWindowTokens = theme.window
    }

    /// Keystrokes go to the focused pane's terminal. The palette and the observatory own the keyboard while open: a
    /// publish (a hook, the minute tick) must not hand it back to a terminal they cover.
    func focusKeyboard(on pane: PaneID?) {
        guard !hasOverlayOpen, let pane, let view = services.engine.view(for: pane), window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)
    }
}
