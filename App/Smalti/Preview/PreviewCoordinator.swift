import AppKit
import GhosttyAdapter
import SmaltiCore

/// One window's image preview (spec F5.5): turns the panes' pointer words into `PreviewUnderPointer` calls with each
/// pane's directory and last command, and shows the card over the pane. Keys, scrolls and losing the window hide it.
@MainActor
final class PreviewCoordinator {
    struct Dependencies {
        let files: any ImageFiles
        let views: any TerminalViewProvider
        /// The pane's last command (the input session is an actor: the answer comes later).
        let lastCommand: (PaneID) async -> String?
    }

    private let window: NSWindow
    private let controller: TilingController
    private let dependencies: Dependencies
    private var preview: PreviewUnderPointer?
    private var cardView: PreviewCardView?
    private var pane: PaneID?
    /// The pane of the word being looked up, before its card shows.
    private var pendingPane: PaneID?
    /// Each pointer word is numbered: an answer for an older one, which the async lookup can deliver late, is dropped.
    private var requests = 0
    private var monitor: Any?
    private let timings = PreviewTimings()
    private var resignObserver: NSObjectProtocol?

    init(window: NSWindow, controller: TilingController, dependencies: Dependencies) {
        self.window = window
        self.controller = controller
        self.dependencies = dependencies
        // Retina's scale whatever screen the window opens on: a sharper thumbnail on a 1x screen costs nothing.
        let scale = Self.thumbnailScale
        let box = controller.theme.previewCard.imageSize
        let wait = TimerDebouncer(delay: PreviewUnderPointer.delay)
        let debouncer: any Debouncer = timings.map { TimedDebouncer(wait, timings: $0) } ?? wait
        preview = PreviewUnderPointer(
            ports: .init(files: dependencies.files, debouncer: debouncer),
            thumbnailSize: Size(width: box.width * scale, height: box.height * scale),
            show: { [weak self] card in self?.show(card) })
        watchForDismissal()
    }

    isolated deinit {
        monitor.map(NSEvent.removeMonitor)
        resignObserver.map(NotificationCenter.default.removeObserver)
    }

    /// The image of the card on screen, for ⌘Y.
    var visibleCard: PreviewCard? { preview?.current }

    /// ⌘Y: closes Quick Look when it shows (the card hid when the panel took the keyboard), or opens it on the card's
    /// image; without either, nothing.
    func toggleQuickLook() {
        (window as? SmaltiWindow)?.quickLook.toggle(visibleCard?.path ?? lastShown)
    }

    /// The image of the last card shown, kept after keys hide it so ⌘K and the menu can still open it (final review
    /// I2: opening either hides the card first). A new hover replaces it.
    private var lastShown: String?

    func pointerWordChanged(_ word: PointerWord?, in pane: PaneID) {
        // Panes report on streams of their own: a late "nothing" from another pane must not drop this one's word.
        guard word != nil || pane == self.pane || pane == pendingPane else { return }
        requests += 1
        let request = requests
        guard let word else {
            pendingPane = nil
            preview?.pointerMoved(nil, context: Self.noContext)
            return
        }
        pendingPane = pane
        lastShown = nil
        let directory = controller.set.workspaces.lazy.flatMap(\.panes).first { $0.id == pane }?.workingDirectory.path
        Task { [weak self, dependencies, home = controller.home.path] in
            let lastCommand = await dependencies.lastCommand(pane)
            guard let self, request == requests else { return }
            self.pane = pane
            let context = PreviewContext(workingDirectory: directory, home: home, lastCommand: lastCommand)
            preview?.pointerMoved(word, context: context)
        }
    }

    func hide() {
        requests += 1
        if let pane { dependencies.views.forgetPointerWord(in: pane) }
        preview?.pointerMoved(nil, context: Self.noContext)
    }

    private static let noContext = PreviewContext(workingDirectory: nil, home: "", lastCommand: nil)
    private static let thumbnailScale = 2.0

    private func watchForDismissal() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown])
        {
            [weak self] event in
            if let self, event.window === window, !isQuickLookKey(event) { hide() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// ⌘Y (or what the keymap binds to Quick Look) uses the card; every other key, shortcuts included, hides it.
    private func isQuickLookKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let chord = KeyChordTranslator.chord(from: event) else { return false }
        return controller.config.keys.command(for: chord) == .previewQuickLook
    }

    private func show(_ card: PreviewCard?) {
        // A pane that left the window (another workspace, closed) has nowhere to show a card.
        guard let card, let pane, let terminal = dependencies.views.view(for: pane), terminal.window === window,
            let content = window.contentView
        else {
            removeCard()
            return
        }
        if let view = cardView, view.theme != controller.theme { removeCard() }
        let view = cardView ?? PreviewCardView(theme: controller.theme)
        view.show(card, shortcut: controller.config.keys.chord(for: .previewQuickLook)?.display)
        if card.thumbnail != nil { lastShown = card.path }
        view.frame = frame(of: view, for: card, in: terminal, to: content)
        if cardView == nil {
            content.addSubview(view)
            cardView = view
            view.appear(isMotionReduced: Motion.isReduced)
        }
        timings?.cardShown()
    }

    private func removeCard() {
        cardView?.removeFromSuperview()
        cardView = nil
    }

    /// The card's frame from `PreviewCardPlacement`, worked out in the terminal's top-left points and turned into the
    /// content view's.
    private func frame(of view: PreviewCardView, for card: PreviewCard, in terminal: NSView, to content: NSView)
        -> NSRect
    {
        let bounds = terminal.bounds
        let size = view.cardSize
        let placed = PreviewCardPlacement.frame(
            size: Size(width: size.width, height: size.height), word: card.anchor,
            pane: Rect(x: 0, y: 0, width: bounds.width, height: bounds.height), gap: view.theme.previewCard.anchorGap)
        let flipped = NSRect(
            x: placed.origin.x, y: bounds.height - placed.origin.y - placed.size.height, width: placed.size.width,
            height: placed.size.height)
        return terminal.convert(flipped, to: content)
    }
}
