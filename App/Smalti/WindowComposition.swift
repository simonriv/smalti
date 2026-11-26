import AppKit
import GhosttyAdapter
import SmaltiCore

/// What a window needs from the app's shared services. The app builds it once; every window gets the same one.
@MainActor
struct WindowServices {
    let engine: GhosttyTerminalEngine
    let harnesses: HarnessRegistry
    /// F6: the session search's state and opener, one per card or restore screen.
    let makeSessionSearch: () -> SessionSearchModel
    /// The window's workspaces, frame or full screen changed: the session keeper and the input coordinator follow.
    let changed: () -> Void
    /// The user chose on the resume screen of the window passed; the app restores every window from it.
    let restoreChosen: (RestoreChoice, SessionSnapshot, WindowComposition) -> Void
    /// ⌘N, ⇧⌘W, ⌘J… (`TilingController.appCommands`), from this window.
    let appCommand: (CommandID, WindowComposition) -> Void
    /// The window became key: it is the front one now.
    let becameFront: (WindowComposition) -> Void
    /// The Tab menu and the ⌃R palette are the app's (one input coordinator for every pane).
    let completionMenu: () -> CompletionMenuController?
    let historyPalette: () -> HistoryPaletteController?
    let openHistory: (PaneID) -> Void
    /// A window opened or closed its observatory; the app counts them all.
    let observatoryOpenChanged: () -> Void
    /// A password prompt in one of this window's panes asks for secure keyboard entry, or releases it.
    let secureInputRequested: (Bool, PaneID) -> Void
    /// F5.5: the image files the preview reads and the panes' last commands.
    let imageFiles: any ImageFiles
    let lastCommand: (PaneID) async -> String?
    /// F8: the processes and ports views' use cases (one set per window) and the names of every window's panes.
    let processes: ProcessesServices
}

/// F8: what a window's processes and ports views need from the app.
@MainActor
struct ProcessesServices {
    let make: () -> ProcessesController.Dependencies
    let grace: Duration
    let paneNames: () -> [PaneID: String]
    /// The group leading each pane's terminal now, in every window.
    let foregroundGroups: () -> [PaneID: Int32]
    /// Shows the pane in whichever window holds it; false when no window does any more.
    let showPane: (PaneID) -> Bool
}

/// One window and everything drawn in it: its tiling controller, palette, observatory overlay, resume screen and
/// keyboard routing. Only `AppComposition` creates it; it builds no infrastructure.
@MainActor
final class WindowComposition {
    let id = WindowID()
    let window: SmaltiWindow
    let controller: TilingController
    private let services: WindowServices
    private var palette: CommandPaletteController?
    private var observatoryScreen: ObservatoryController?
    /// F8: ⌘⇧M and ⌘⇧U, the processes and ports views over the window.
    private var processesScreen: ProcessesController?
    private var help: HelpController?
    /// F6: ⌘⇧O, the session search card.
    private var sessions: SessionSearchController?
    /// F5 ⌘,: the Appearance aside, created on first use with the app's session.
    private var appearancePanel: AppearancePanelController?
    /// F5 ⇧⌘P: the prompt studio over the whole window.
    private var studio: PromptStudioController?
    private var search: SearchBarController?
    private var feedback: FeedbackController?
    private var welcome: WelcomeController?
    /// F5.5: the image preview card over this window's panes.
    private(set) var preview: PreviewCoordinator?
    private var restoreScreen: RestoreController?
    /// What the glass was last painted with, so a publish that does not change it repaints nothing.
    private var appliedWindowTokens: WindowTokens?
    private var observers: [NSObjectProtocol] = []
    /// The frame outside full screen: what the session saves while the window is full screen, and what ⌘N cascades
    /// from, so leaving full screen after a restore gives the window its own size back.
    private(set) var windowedFrame: Rect

    init(window: SmaltiWindow, controller: TilingController, services: WindowServices) {
        self.window = window
        self.controller = controller
        self.services = services
        windowedFrame = Rect(window.frame)
        applyGlass(controller.theme)
        connect()
        observeWindow()
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// What the session saves of this window. Frames are AppKit screen coordinates (`WindowFrame`).
    var state: WindowState {
        WindowState(
            id: id, workspaces: controller.set, frame: windowedFrame,
            isFullScreen: window.styleMask.contains(.fullScreen))
    }

    /// Moves the window to a saved frame, refitted to the visible part of the screens there are now (below the menu
    /// bar, beside the Dock), and lays it out so panes restored next get the right area.
    func place(at saved: Rect) {
        let screens = NSScreen.screens.map { Rect($0.visibleFrame) }
        let fitted = WindowFrame.fitted(saved, screens: screens, main: screens.first ?? saved)
        window.setFrame(NSRect(fitted), display: true)
        windowedFrame = fitted
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Tells the app when the user moves, resizes, focuses or takes the window full screen.
    private func observeWindow() {
        let center = NotificationCenter.default
        let changes: [Notification.Name] = [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
        ]
        observers += changes.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowChanged() }
            }
        }
        for (name, isChanging) in [
            (NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, true),
            (NSWindow.didEnterFullScreenNotification, false), (NSWindow.didExitFullScreenNotification, false),
        ] {
            observers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.isChangingFullScreen = isChanging }
                })
        }
        observers.append(
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.services.becameFront(self)
                }
            })
    }

    private func windowChanged() {
        let isFullScreen = window.styleMask.contains(.fullScreen)
        window.showsFullScreenChrome(isFullScreen)
        // Entering and leaving full screen also move and resize the window: only frames outside it are kept.
        if !isFullScreen, !isChangingFullScreen { windowedFrame = Rect(window.frame) }
        services.changed()
    }

    /// Between `willEnter`/`willExit` and `didEnter`/`didExit` full screen, the frame is the animation's.
    private var isChangingFullScreen = false

    var isAskingToRestore: Bool { restoreScreen != nil }

    var isObservatoryOpen: Bool { observatoryScreen?.isOpen == true }

    /// A palette, the observatory or the ⌃R palette owns the keyboard.
    var hasOverlayOpen: Bool {
        palette?.isOpen == true || observatoryScreen?.isOpen == true || processesScreen?.isOpen == true
            || hasHistoryPaletteOpen
            || help?.isOpen == true || search?.isOpen == true || feedback?.isOpen == true
            || welcome?.isOpen == true
    }

    /// F7.7: one card for the whole app, so another window does not open a second one.
    var hasWelcomeOpen: Bool { welcome?.isOpen == true }

    /// F7.7: the welcome card in this window.
    func showWelcome(actions: WelcomeActions) {
        closeOverlays(keeping: .welcome)
        welcome?.open(
            theme: controller.theme, keymap: controller.config.keys,
            currentTheme: controller.config.appearance.theme, actions: actions)
    }

    /// "Reportar un problema o una idea" in this window; `submit` gets the kind and whether to save the logs.
    func showFeedback(summary: String, submit: @escaping (FeedbackKind, Bool) -> Void) {
        closeOverlays(keeping: .feedback)
        feedback?.open(theme: controller.theme, summary: summary, submit: submit)
    }

    /// The window's own overlays. One at a time: opening one closes the others, so the keyboard always has a
    /// single place to go when the top one closes (block 4 review).
    enum Overlay {
        case palette, help, search, feedback, sessions, welcome
    }

    func closeOverlays(keeping kept: Overlay? = nil) {
        if kept != .palette { palette?.close() }
        if kept != .help { help?.close() }
        if kept != .search { search?.dismiss() }
        if kept != .feedback { feedback?.close() }
        if kept != .sessions { sessions?.close() }
        if kept != .welcome { welcome?.close() }
    }

    /// ⌘, (spec F5): opens or closes the Appearance aside of this window.
    func toggleAppearance(_ session: AppearanceSession) {
        let panel =
            appearancePanel
            ?? {
                let panel = AppearancePanelController(window: window, session: session)
                panel.onOpenChange = { [weak self] isOpen in
                    guard let self, !isOpen else { return }
                    focusKeyboard(on: controller.set.active.focusedPane)
                }
                appearancePanel = panel
                return panel
            }()
        closeOverlays()
        panel.toggle()
    }

    /// ⇧⌘P (spec F5): the studio covers the window; the panes behind it are hidden but keep running.
    func toggleStudio(_ session: AppearanceSession) {
        let studio =
            self.studio
            ?? {
                let studio = PromptStudioController(window: window, session: session)
                studio.hasOverlayOnTop = { [weak self] in self?.palette?.isOpen == true || self?.help?.isOpen == true }
                studio.onOpenChange = { [weak self] isOpen in
                    guard let self else { return }
                    setTilingHidden(isOpen)
                    if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
                }
                self.studio = studio
                return studio
            }()
        closeOverlays()
        appearancePanel?.close()
        studio.toggle()
    }

    /// ⌘K's studio commands act only while it is open in this window.
    func performInStudio(_ edit: PromptStudioEdit) {
        guard studio?.isOpen == true else { return }
        studio?.perform(edit)
    }

    func closeStudio() {
        studio?.close()
    }

    func closeAppearancePanel() {
        appearancePanel?.close()
    }

    func refreshAppearancePanel() {
        appearancePanel?.refresh()
    }

    func dismissObservatory() {
        observatoryScreen?.dismiss()
        processesScreen?.dismiss()
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
            services.restoreChosen(.restore(.defaults(for: snapshot)), snapshot, self)
            return
        }
        let listing = RestoreController.Content(
            snapshot: snapshot,
            windows: ResumeListing.windows(
                in: snapshot,
                context: ResumeListing.Context(
                    home: controller.home, harnesses: services.harnesses, texts: .current)),
            closedAt: ClosedAtPhrase.text(
                closedAt: snapshot.savedAt, now: .now, calendar: .current, texts: .current))
        let screen = RestoreController(
            listing, theme: controller.theme, preferences: preferences, sessions: services.makeSessionSearch()
        ) {
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
        restoreScreen?.stop()
        restoreScreen?.view.removeFromSuperview()
        restoreScreen = nil
        setTilingHidden(false)
        services.restoreChosen(choice, snapshot, self)
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
            window.buttons?.apply(state.config.window.buttons, theme: state.theme)
            window.strip.render(state)
            window.paneGrid.render(state) { engine.view(for: $0) }
            window.statusBar.render(state)
            welcome?.restyle(state.theme)
            // The Window menu's list of windows names each by its active workspace.
            window.title = state.set.active.name
            labelTerminals(state.set.active)
            search?.follow(state.set)
            focusKeyboard(on: state.set.active.focusedPane)
            services.changed()
        }
        controller.onObservatoryChange = { [weak self] state in
            guard let self else { return }
            window.paneGrid.render(state) { engine.view(for: $0) }
            window.statusBar.render(state)
        }
        grid.onPaneClicked = { [weak controller] pane in controller?.focus(pane) }
        window.strip.onCommand = { [weak controller] command in controller?.perform(command) }
        window.strip.onCursor = { [weak window] isInside in window?.buttons?.cursorOnStrip(isInside) }
        window.buttons?.onShow = { [weak window] faded in
            window?.strip.setAccessibilityValue(
                faded ? String(localized: "buttons with fade") : String(localized: "buttons without fade"))
        }
        window.onCloseRequest = { [weak self] in
            guard let self else { return }
            services.appCommand(.windowClose, self)
        }
        controller.onAppCommand = { [weak self] command in
            guard let self else { return }
            services.appCommand(command, self)
        }
        controller.onConfirmClose = { [weak self] question, proceed in
            guard let self else { return }
            CloseConfirmation.ask(question, in: window) { confirmed in if confirmed { proceed() } }
        }
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
                    return SearchCommands(layouts: .standard, texts: .current).execute(
                        query, state: controller.catalogState(), keymap: controller.config.keys)
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
            // F5.6: the integration may have changed outside Smalti; a new state rebuilds the open list.
            if isOpen { controller.refreshIntegrationState() }
        }
        // F5.6: a new Claude integration state rebuilds the open palette's list.
        observers.append(
            NotificationCenter.default.addObserver(forName: .claudeIntegrationChanged, object: nil, queue: .main) {
                [weak palette] _ in
                MainActor.assumeIsolated { palette?.catalogChanged() }
            })
        let help = HelpController(
            window: window, keymap: { [weak controller] in controller?.config.keys ?? .standard },
            perform: { [weak controller] command in controller?.perform(command) })
        help.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
            if isOpen { services.completionMenu()?.close() }
        }
        self.help = help
        let sessions = SessionSearchController(
            window: window, model: services.makeSessionSearch(),
            open: { [weak controller] plan, directory in controller?.openHarnessSession(plan, directory: directory) })
        sessions.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
            if isOpen { services.completionMenu()?.close() }
        }
        self.sessions = sessions
        let search = SearchBarController(window: window, engine: services.engine)
        search.onClose = { [weak self] pane in self?.focusKeyboard(on: pane) }
        self.search = search
        let feedback = FeedbackController(window: window)
        feedback.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
        }
        self.feedback = feedback
        let welcome = WelcomeController(window: window)
        welcome.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            window.paneGrid.alphaValue = isOpen ? controller.theme.palette.panelsBackdropOpacity : 1
            if !isOpen { focusKeyboard(on: controller.set.active.focusedPane) }
        }
        self.welcome = welcome
        preview = PreviewCoordinator(
            window: window, controller: controller,
            dependencies: .init(
                files: services.imageFiles, views: services.engine, lastCommand: services.lastCommand))
        controller.onViewEvent = { [weak self, weak search] event, pane in
            switch event {
            case .linkHovered(let url): self?.controller.showHoveredLink(url)
            case .pointerWordChanged(let word): self?.preview?.pointerWordChanged(word, in: pane)
            case .secureInputRequested(let isOn): self?.services.secureInputRequested(isOn, pane)
            default: search?.progress(event, from: pane)
            }
        }
        let screen = makeObservatoryScreen()
        observatoryScreen = screen
        let processes = makeProcessesScreen()
        processesScreen = processes
        controller.onViewCommand = { [weak self, weak palette, weak screen, weak processes] command in
            guard let self, let palette else { return }
            let theme = controller.theme
            switch command {
            case .workspaceRename: palette.beginRename(theme: theme)
            case .observatoryToggle: screen?.toggle(theme: theme)
            case .observatoryPeriod: screen?.cyclePeriod()
            // From ⌘K or the menu with the observatory closed, it opens it first.
            case .observatoryFilter:
                if screen?.isOpen == true { screen?.cycleFilter() } else { screen?.toggle(theme: theme) }
            case .historySearch:
                if let pane = controller.set.active.focusedPane { services.openHistory(pane) }
            case .previewQuickLook:
                self.preview?.toggleQuickLook()
            case .helpShow:
                closeOverlays(keeping: .help)
                self.help?.toggle(theme: theme)
            case .searchOpen:
                closeOverlays(keeping: .search)
                if let pane = controller.set.active.focusedPane { self.search?.open(on: pane, theme: theme) }
            case .searchNext, .searchPrevious:
                guard let search = self.search, let pane = controller.set.active.focusedPane else { return }
                closeOverlays(keeping: .search)
                if !search.isOpen { search.open(on: pane, theme: theme) }
                search.navigate(command == .searchNext ? .next : .previous)
            case .paletteOpen:
                closeOverlays(keeping: .palette)
                palette.toggle(theme: theme)
            case .harnessSearch:
                closeOverlays(keeping: .sessions)
                self.sessions?.toggle(theme: theme)
            case .processesToggle, .portsToggle:
                closeOverlays()
                processes?.toggle(command == .portsToggle ? .ports : .processes, theme: theme)
            // From ⌘K or the menu with the view closed, they open it first.
            case .processesStop, .processesLowerPriority, .processesTree, .processesSort:
                if processes?.isOpen != true { closeOverlays() }
                processes?.perform(command, theme: theme)
            default: break
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
                    self?.services.observatoryOpenChanged()
                    if isOpen { self?.services.completionMenu()?.close() }
                }))
    }

    /// ⌘⇧M / ⌘⇧U: the processes and ports views over the window; ↵ on a pane's row shows that pane, in whichever
    /// window holds it.
    private func makeProcessesScreen() -> ProcessesController {
        let processes = services.processes
        return ProcessesController(
            window: window, dependencies: processes.make(),
            actions: .init(
                setTilingHidden: { [weak self] hidden in self?.setTilingHidden(hidden) },
                didClose: { [weak self] pane in
                    guard let self else { return }
                    if pane.map(processes.showPane) != true { focusKeyboard(on: controller.set.active.focusedPane) }
                },
                foregroundGroups: processes.foregroundGroups,
                paneNames: processes.paneNames,
                keymap: { [weak self] in self?.controller.config.keys ?? .standard }),
            grace: processes.grace)
    }

    private func connectKeyboard() {
        let router = KeyRouter(
            keymap: { [weak controller] in controller?.config.keys ?? .standard },
            context: { [weak self] in self?.keyContext ?? .unrestricted },
            perform: { [weak controller] command in controller?.perform(command) })
        // The resume screen owns the keyboard: no tiling shortcut acts, and its own keys reach it untouched.
        window.routeKey = { [weak self] event, composing in
            guard let self, restoreScreen == nil else { return false }
            // The Tab menu and the ⌃R palette are shared by every window: only their own window's keys are theirs.
            if !composing, services.completionMenu()?.handle(event, in: window) == true { return true }
            if hasHistoryPaletteOpen, services.historyPalette()?.handle(event) == true { return true }
            return router.route(event, composing: composing)
        }
    }

    /// An open palette lets only ⌘K through; an open observatory only ⌘⇧A and ⌘P (its own keys reach its view); ⌘P
    /// reaches the terminal while the observatory is closed.
    /// What the menu bar may do on this window: what its keyboard may, and on the resume screen only what does not
    /// touch the workspaces it is about to replace.
    var menuContext: KeyContext {
        restoreScreen == nil ? keyContext : KeyContext(allowing: Self.allowedOnResumeScreen)
    }

    private static let allowedOnResumeScreen: Set<CommandID> = [.windowNew, .appAbout, .configOpen]

    /// The ⌃R palette is open in this window (it is shared by all of them).
    private var hasHistoryPaletteOpen: Bool {
        services.historyPalette()?.isOpen(in: window) == true
    }

    private var keyContext: KeyContext {
        if palette?.isOpen == true { return .overlay(allowing: [.paletteOpen, .helpShow]) }
        // F7.5 review 2: the approval keys are no text keys; they decide even over the help or the search bar.
        if help?.isOpen == true { return .overlay(allowing: [.helpShow, .paletteOpen, .guardApprove, .guardReject]) }
        // F5: in the studio ⌘↑ and ⌘↓ move modules; only its own commands, ⌘K and the help act. ⌘K and the help
        // on top of it come first (block 5 review, M3).
        if studio?.isOpen == true {
            return .panel(allowing: [.promptStudio, .promptApply, .promptExport, .paletteOpen, .helpShow])
        }
        // The feedback box has no text field: ⌘C, ⌘V and ⌘A must not reach the terminal behind it either.
        if feedback?.isOpen == true || welcome?.isOpen == true { return KeyContext(allowing: []) }
        if search?.isOpen == true {
            return .overlay(allowing: [
                .searchOpen, .searchNext, .searchPrevious, .paletteOpen, .helpShow, .guardApprove, .guardReject,
            ])
        }
        // The ⌃R palette owns the keyboard: no tiling shortcut acts while it is open.
        if hasHistoryPaletteOpen { return .overlay(allowing: []) }
        // F6: the ⌘⇧O card owns the keyboard (⌘1…⌘5 change its chips, ⌘V pastes in its field).
        if sessions?.isOpen == true {
            return .overlay(allowing: [.harnessSearch, .paletteOpen, .helpShow, .guardApprove, .guardReject])
        }
        if observatoryScreen?.isOpen == true {
            return KeyContext(allowing: [.observatoryToggle, .observatoryPeriod, .observatoryFilter])
        }
        // F8: the view owns the keyboard (typing filters); only its own chords act.
        if processesScreen?.isOpen == true { return KeyContext(allowing: Set(CommandID.processes)) }
        return KeyContext(
            passingThrough: Set([CommandID.observatoryPeriod, .observatoryFilter]).union(CommandID.processesContextual))
    }

    /// VoiceOver names each terminal "Terminal, panel 2, zsh"; its value is the visible text (`GhosttySurfaceView`).
    private func labelTerminals(_ workspace: Workspace) {
        for (index, pane) in workspace.panes.enumerated() {
            services.engine.view(for: pane.id)?.setAccessibilityLabel(
                String(localized: "Terminal, pane \(index + 1), \(pane.headerName.isEmpty ? "shell" : pane.headerName)")
            )
        }
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
        guard !hasOverlayOpen, appearancePanel?.ownsKeyboard != true, studio?.isOpen != true, let pane,
            let view = services.engine.view(for: pane), window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)
    }
}
