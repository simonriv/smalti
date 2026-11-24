import AppKit
import SmaltiCore

/// Borderless-looking glass window: no traffic lights, rounded, dragged from the top strip.
final class SmaltiWindow: NSWindow {
    /// Window size of the approved design boards (docs/design/README.md).
    static let defaultContentSize = NSSize(width: 1328, height: 820)
    static let minimumContentSize = NSSize(width: 480, height: 300)

    let paneGrid: PaneGridView
    let strip: WorkspaceStripView
    let statusBar: StatusBarView
    private let content: WindowContentView
    /// Smalti shortcuts are routed before AppKit or the terminal see the key (`KeyRouter`).
    var routeKey: ((NSEvent, _ isComposing: Bool) -> Bool)?

    init(theme: Theme) {
        let content = WindowContentView(theme: theme)
        self.content = content
        paneGrid = content.paneGrid
        strip = content.strip
        statusBar = content.statusBar
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            // No `.closable`: windows close only through ⇧⌘W, which asks first and closes their panes (F4.5).
            styleMask: [.titled, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // AppComposition owns the window; AppKit must not release it again on close.
        isReleasedWhenClosed = false
        isOpaque = GlassProbe.current == .opaque
        backgroundColor = GlassProbe.current == .opaque ? .black : .clear
        hasShadow = GlassProbe.current != .noShadow
        contentMinSize = Self.minimumContentSize
        contentView = content
        setContentSize(Self.defaultContentSize)
        setAccessibilityIdentifier("smalti.window")
        // F4.5: native full screen (⌃⌘F); the traffic lights stay hidden (window buttons are F5).
        collectionBehavior.insert(.fullScreenPrimary)
        center()
    }

    /// In full screen the glass loses its rounded corners and border: they would frame the whole screen.
    func showsFullScreenChrome(_ isFullScreen: Bool) {
        content.showsFullScreenChrome(isFullScreen)
    }

    /// Paints the glass (tint, border, blur) from `theme.window`. Needs the window on screen for the blur.
    func applyGlass(_ theme: Theme) {
        let radius = GlassProbe.current == .noBlur ? 0 : theme.window.blurRadius
        let blur = WindowGlass.apply(blurRadius: radius, to: self)
        content.apply(theme.window, blur: blur)
    }

    /// ⌘ shortcuts arrive here first, before the menu and the terminal's own key equivalents.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        routeKey?(event, isComposing) == true || super.performKeyEquivalent(with: event)
    }

    /// Shortcuts without ⌘ (⌃1…⌃9) arrive as plain key-down events.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, routeKey?(event, isComposing) == true { return }
        super.sendEvent(event)
    }

    /// The first responder is in the middle of a dead key or an IME composition.
    private var isComposing: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}

/// Rounded glass surface: workspace strip (40 pt), pane area with a 10 pt margin, status bar (28 pt).
final class WindowContentView: NSView {
    let paneGrid: PaneGridView
    let strip: WorkspaceStripView
    let statusBar: StatusBarView

    init(theme: Theme) {
        paneGrid = PaneGridView(theme: theme)
        strip = WorkspaceStripView(theme: theme)
        statusBar = StatusBarView(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.window.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = GlassProbe.current != .noMask
        paint(theme.window)
        layoutChrome(theme: theme)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.glass")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }

    /// Repaints the glass and states what was applied as the accessibility value, e.g. "vidrio 0.62 · desenfoque 28",
    /// read back from the layer so tests see what is on screen rather than what was asked for.
    func apply(_ tokens: WindowTokens, blur: GlassBlur) {
        paint(tokens)
        let opacity = layer?.backgroundColor?.alpha ?? 0
        setAccessibilityValue("vidrio \(String(format: "%.2f", opacity)) · desenfoque \(blur.description)")
    }

    /// F4.5: square and borderless in full screen; the tokens again when it leaves.
    func showsFullScreenChrome(_ isFullScreen: Bool) {
        self.isFullScreen = isFullScreen
        if let tokens = paintedTokens { paint(tokens) }
        setAccessibilityHelp(isFullScreen ? "pantalla completa" : nil)
    }

    private var isFullScreen = false
    private var paintedTokens: WindowTokens?

    private func paint(_ tokens: WindowTokens) {
        paintedTokens = tokens
        layer?.cornerRadius = isFullScreen ? 0 : tokens.cornerRadius
        layer?.borderWidth = isFullScreen ? 0 : tokens.borderWidth
        layer?.borderColor = tokens.border.nsColor.cgColor
        layer?.backgroundColor = tokens.background.nsColor.cgColor
    }

    private func layoutChrome(theme: Theme) {
        let padding = theme.panel.areaPadding
        for view in [strip, paneGrid, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: theme.chrome.topStripHeight),
            paneGrid.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: padding),
            paneGrid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            paneGrid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            paneGrid.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -padding),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: theme.statusBar.height),
        ])
    }
}

extension GlassBlur {
    fileprivate var description: String {
        switch self {
        case .exact(let radius): "\(radius)"
        case .systemMaterial: "del sistema"
        }
    }
}
