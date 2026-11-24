import AppKit
import SmaltiCore

/// The native traffic lights of a glass window (spec F5, "Botones de ventana"): hidden, shown while the cursor is on
/// the strip, or always visible, centered in the 40 px strip at the places of `mockup-buttons`.
@MainActor
final class WindowButtonsController {
    private unowned let window: NSWindow
    private var mode = WindowButtons.hidden
    private var tokens: WindowButtonTokens
    private var fadeDuration: Double
    private var stripHeight: Double
    private var isShown = false
    /// In full screen the buttons are macOS's (spec F5): shown, where AppKit puts them (block 4 review, I4).
    private var isFullScreen = false
    private var frameObservers: [NSObjectProtocol] = []
    /// States how the buttons last appeared ("botones con fundido" / "botones sin fundido"), for tests (C15).
    var onShow: ((_ faded: Bool) -> Void)?

    private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    init(window: NSWindow, theme: Theme) {
        self.window = window
        tokens = theme.strip.windowButtons
        fadeDuration = theme.motion.windowButtonsFade
        stripHeight = theme.chrome.topStripHeight
        makeZoomZoom()
        followAppKitLayout()
        setShown(false, faded: false)
    }

    /// Entering or leaving full screen.
    func setFullScreen(_ isFullScreen: Bool) {
        guard isFullScreen != self.isFullScreen else { return }
        self.isFullScreen = isFullScreen
        guard !isFullScreen else {
            buttons.forEach {
                $0.isHidden = false
                $0.alphaValue = 1
            }
            return
        }
        makeZoomZoom()
        setShown(mode.isAlwaysShown, faded: false)
    }

    /// Spec: Zoom is `performZoom`, as in the Window menu, not full screen (that is ⌃⌘F). AppKit may set its own
    /// action again after full screen, so it is set on every return.
    private func makeZoomZoom() {
        let zoom = window.standardWindowButton(.zoomButton)
        zoom?.target = window
        zoom?.action = #selector(NSWindow.performZoom(_:))
    }

    /// AppKit lays the traffic lights out again on its own (title bar layout, screen or appearance changes): each
    /// time one moves, they go back to the strip's places (block 4 review, I3).
    private func followAppKitLayout() {
        frameObservers = buttons.map { button in
            button.postsFrameChangedNotifications = true
            return NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: button, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.place() }
            }
        }
    }

    func apply(_ mode: WindowButtons, theme: Theme) {
        tokens = theme.strip.windowButtons
        fadeDuration = theme.motion.windowButtonsFade
        stripHeight = theme.chrome.topStripHeight
        guard mode != self.mode else { return place() }
        self.mode = mode
        guard !isFullScreen else { return }
        // Block 4 review (M4): switching to `hover` with the cursor already on the strip shows them now.
        setShown(mode.isAlwaysShown || (mode.followsCursor && isCursorOnStrip), faded: false)
    }

    /// The cursor entered or left the strip.
    func cursorOnStrip(_ isInside: Bool) {
        guard mode.followsCursor, !isFullScreen, isInside != isShown else { return }
        setShown(isInside, faded: !Motion.isReduced && fadeDuration > 0)
    }

    /// AppKit lays the buttons out again on resize and full screen: they go back to the strip's places.
    func place() {
        guard !isFullScreen else { return }
        for (index, button) in buttons.enumerated() {
            guard let container = button.superview else { continue }
            let size = button.frame.size
            let centerX = tokens.firstCenterX + Double(index) * tokens.spacing
            let centerFromTop = stripHeight / 2
            let y =
                container.isFlipped
                ? centerFromTop - size.height / 2 : container.bounds.height - centerFromTop - size.height / 2
            let origin = NSPoint(x: centerX - size.width / 2, y: y)
            // Setting the same origin posts nothing; a different one moves it back once.
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    /// The cursor is over the top strip of the window (window coordinates grow upward).
    private var isCursorOnStrip: Bool {
        let point = window.mouseLocationOutsideOfEventStream
        let size = window.frame.size
        return (0...size.width).contains(point.x) && (size.height - stripHeight...size.height).contains(point.y)
    }

    private var buttons: [NSButton] { Self.types.compactMap { window.standardWindowButton($0) } }

    private func setShown(_ shown: Bool, faded: Bool) {
        isShown = shown
        place()
        let buttons = buttons
        guard faded else {
            buttons.forEach {
                $0.isHidden = !shown
                $0.alphaValue = 1
            }
            if shown { onShow?(false) }
            return
        }
        if shown {
            buttons.forEach {
                $0.alphaValue = 0
                $0.isHidden = false
            }
            onShow?(true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            buttons.forEach { $0.animator().alphaValue = shown ? 1 : 0 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                buttons.forEach { $0.isHidden = true }
            }
        }
    }
}
