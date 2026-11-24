import AppKit
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
    /// Each pointer word is numbered: an answer for an older one, which the async lookup can deliver late, is dropped.
    private var requests = 0
    private var monitor: Any?
    private let timings = PreviewTimings()
    private var resignObserver: NSObjectProtocol?

    init(window: NSWindow, controller: TilingController, dependencies: Dependencies) {
        self.window = window
        self.controller = controller
        self.dependencies = dependencies
        let scale = window.backingScaleFactor
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
        (window as? SmaltiWindow)?.quickLook.toggle(visibleCard?.path)
    }

    func pointerWordChanged(_ word: PointerWord?, in pane: PaneID) {
        requests += 1
        let request = requests
        guard let word else {
            preview?.pointerMoved(nil, context: Self.noContext)
            return
        }
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
        preview?.pointerMoved(nil, context: Self.noContext)
    }

    private static let noContext = PreviewContext(workingDirectory: nil, home: "", lastCommand: nil)

    private func watchForDismissal() {
        // A shortcut (⌘Y above all) is a command, not typing: it leaves the card for the command to use.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            let isShortcut = event.type == .keyDown && event.modifierFlags.contains(.command)
            if event.window === self?.window, !isShortcut { self?.hide() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func show(_ card: PreviewCard?) {
        guard let card, let pane, let terminal = dependencies.views.view(for: pane),
            let content = window.contentView
        else {
            cardView?.removeFromSuperview()
            cardView = nil
            return
        }
        let view = cardView ?? PreviewCardView(theme: controller.theme)
        view.show(card)
        view.frame = CardPlacement.frame(
            size: view.cardSize, anchor: anchorRect(card.anchor, in: terminal, to: content),
            pane: terminal.convert(terminal.bounds, to: content))
        if cardView == nil {
            content.addSubview(view)
            cardView = view
            view.appear(isMotionReduced: Motion.isReduced)
        }
        timings?.cardShown()
    }

    /// The word's frame (top-left points of the terminal view) in the content view's coordinates.
    private func anchorRect(_ anchor: Rect, in terminal: NSView, to content: NSView) -> NSRect {
        let flipped = NSRect(
            x: anchor.origin.x, y: terminal.bounds.height - anchor.origin.y - anchor.size.height,
            width: anchor.size.width, height: anchor.size.height)
        return terminal.convert(flipped, to: content)
    }
}

/// Where the card goes (spec F5.5): under the word, aligned to its start; over it when there is no room below; never
/// out of the pane. AppKit coordinates (y grows up).
enum CardPlacement {
    static let gap: CGFloat = 4

    static func frame(size: NSSize, anchor: NSRect, pane: NSRect) -> NSRect {
        let below = anchor.minY - gap - size.height
        let y = below >= pane.minY ? below : min(anchor.maxY + gap, pane.maxY - size.height)
        let x = max(pane.minX, min(anchor.minX, pane.maxX - size.width))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
