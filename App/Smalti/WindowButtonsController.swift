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
    /// States how the buttons last appeared ("botones con fundido" / "botones sin fundido"), for tests (C15).
    var onShow: ((_ faded: Bool) -> Void)?

    private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    init(window: NSWindow, theme: Theme) {
        self.window = window
        tokens = theme.strip.windowButtons
        fadeDuration = theme.motion.windowButtonsFade
        stripHeight = theme.chrome.topStripHeight
        // Spec: Zoom is `performZoom`, as in the Window menu, not full screen (that is ⌃⌘F).
        let zoom = window.standardWindowButton(.zoomButton)
        zoom?.target = window
        zoom?.action = #selector(NSWindow.performZoom(_:))
        setShown(false, faded: false)
    }

    func apply(_ mode: WindowButtons, theme: Theme) {
        tokens = theme.strip.windowButtons
        fadeDuration = theme.motion.windowButtonsFade
        stripHeight = theme.chrome.topStripHeight
        guard mode != self.mode else { return place() }
        self.mode = mode
        setShown(mode.isAlwaysShown, faded: false)
    }

    /// The cursor entered or left the strip.
    func cursorOnStrip(_ isInside: Bool) {
        guard mode.followsCursor, isInside != isShown else { return }
        setShown(isInside, faded: !Motion.isReduced && fadeDuration > 0)
    }

    /// AppKit lays the buttons out again on resize and full screen: they go back to the strip's places.
    func place() {
        for (index, button) in buttons.enumerated() {
            guard let container = button.superview else { continue }
            let size = button.frame.size
            let centerX = tokens.firstCenterX + Double(index) * tokens.spacing
            let centerFromTop = stripHeight / 2
            let y =
                container.isFlipped
                ? centerFromTop - size.height / 2 : container.bounds.height - centerFromTop - size.height / 2
            button.setFrameOrigin(NSPoint(x: centerX - size.width / 2, y: y))
        }
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
