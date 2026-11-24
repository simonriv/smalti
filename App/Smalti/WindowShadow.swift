import AppKit
import SmaltiCore

/// The glass window's shadow, painted once in a click-through child window behind it (issue #5).
///
/// The system shadow of a non-opaque window is recomputed by WindowServer from the window's alpha every time its
/// content changes (every terminal frame): measured at ~28 points of GPU at rest and ~34 with content moving behind
/// (F5 T13). This shadow is a layer with a fixed `shadowPath` in a window whose content never changes, so it is drawn
/// once per size and only composited afterwards.
@MainActor
final class WindowShadow {
    private let window: ShadowWindow
    private let shadow = CALayer()
    private let outsideOnly = CAShapeLayer()
    private var tokens: WindowTokens

    init(tokens: WindowTokens) {
        self.tokens = tokens
        window = ShadowWindow()
        let root = CALayer()
        window.contentView = NSView()
        window.contentView?.layer = root
        window.contentView?.wantsLayer = true
        shadow.shadowColor = NSColor.black.cgColor
        // The panel is translucent: only the part of the shadow outside the glass is kept, as CSS paints it.
        outsideOnly.fillRule = .evenOdd
        shadow.mask = outsideOnly
        root.addSublayer(shadow)
        paint()
    }

    /// Puts the shadow behind `parent`; safe to call again.
    func attach(to parent: NSWindow) {
        guard window.parent !== parent else { return }
        parent.addChildWindow(window, ordered: .below)
        follow(parent.frame)
    }

    func restyle(_ tokens: WindowTokens) {
        guard tokens.shadow != self.tokens.shadow || tokens.cornerRadius != self.tokens.cornerRadius else { return }
        self.tokens = tokens
        paint()
        if let parent = window.parent { follow(parent.frame) }
    }

    /// Resizes the shadow to a new glass frame (screen coordinates).
    func follow(_ glass: NSRect) {
        let reach = Self.reach(of: tokens.shadow)
        window.setFrame(glass.insetBy(dx: -reach, dy: -reach), display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: window.frame.size)
        let glassRect = bounds.insetBy(dx: reach, dy: reach)
        let radius = tokens.cornerRadius
        shadow.frame = bounds
        shadow.shadowPath = CGPath(roundedRect: glassRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(CGPath(roundedRect: glassRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        outsideOnly.frame = bounds
        outsideOnly.path = outside
        CATransaction.commit()
    }

    /// Full screen has no shadow.
    func setVisible(_ isVisible: Bool) {
        window.alphaValue = isVisible ? 1 : 0
    }

    func close() {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    /// How far the shadow reaches beyond the glass: CSS blur fades out at about its full length past the offset.
    private static func reach(of shadow: WindowShadowTokens) -> Double {
        shadow.blur + abs(shadow.offsetY)
    }

    private func paint() {
        shadow.shadowOpacity = Float(tokens.shadow.opacity)
        // CSS blur radius is twice the Core Animation shadow radius.
        shadow.shadowRadius = tokens.shadow.blur / 2
        // CSS y grows downward; the layer's y grows upward.
        shadow.shadowOffset = CGSize(width: 0, height: -tokens.shadow.offsetY)
    }
}

/// Borderless, transparent and click-through; never key, never in the window list or the accessibility tree.
private final class ShadowWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
}
