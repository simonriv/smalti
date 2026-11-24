import AppKit
import Quartz
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
    /// Drawn once in a child window instead of the system shadow (issue #5, F5 T13).
    private let shadow: WindowShadow
    private var resizeObserver: NSObjectProtocol?
    /// F5 window buttons; created once the window exists.
    private(set) var buttons: WindowButtonsController?
    /// The close button asks like ⇧⌘W (spec F5); AppKit never closes the window by itself.
    var onCloseRequest: (() -> Void)?
    /// F5.5 ⌘Y: the Quick Look panel's source while this window controls it.
    let quickLook = QuickLookPresenter()

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLook
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }
    /// Smalti shortcuts are routed before AppKit or the terminal see the key (`KeyRouter`).
    var routeKey: ((NSEvent, _ isComposing: Bool) -> Bool)?

    init(theme: Theme) {
        let content = WindowContentView(theme: theme)
        self.content = content
        paneGrid = content.paneGrid
        strip = content.strip
        statusBar = content.statusBar
        shadow = WindowShadow(tokens: theme.window)
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            // `.closable` for the F5 close button; `performClose` routes it through ⇧⌘W's question.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // AppComposition owns the window; AppKit must not release it again on close.
        isReleasedWhenClosed = false
        isOpaque = GlassProbe.current == .opaque
        backgroundColor = GlassProbe.current == .opaque ? .black : .clear
        hasShadow = GlassProbe.current == .systemShadow
        contentMinSize = Self.minimumContentSize
        contentView = content
        setContentSize(Self.defaultContentSize)
        setAccessibilityIdentifier("smalti.window")
        // F4.5: native full screen (⌃⌘F); F5 window buttons follow `[window] buttons` (WindowButtonsController).
        collectionBehavior.insert(.fullScreenPrimary)
        center()
        buttons = WindowButtonsController(window: self, theme: theme)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.shadow.follow(self.frame)
                self.buttons?.place()
            }
        }
    }

    /// The close button and the Window menu's "Cerrar" ask first (spec F5); the app decides and closes.
    override func performClose(_ sender: Any?) {
        onCloseRequest?()
    }

    override func close() {
        shadow.close()
        // Block 4 review (M1): the observer goes with the window.
        resizeObserver.map(NotificationCenter.default.removeObserver)
        resizeObserver = nil
        buttons?.stop()
        super.close()
    }

    /// In full screen the glass loses its rounded corners and border: they would frame the whole screen.
    func showsFullScreenChrome(_ isFullScreen: Bool) {
        content.showsFullScreenChrome(isFullScreen)
        shadow.setVisible(!isFullScreen)
        buttons?.setFullScreen(isFullScreen)
        buttons?.place()
    }

    /// F5 Apariencia and Estudio: an aside on the right; the strip, the panes and the status bar shrink to its left.
    func showSidePanel(_ panel: NSView?, width: Double) {
        content.showSidePanel(panel, width: width)
    }

    /// Paints the glass (tint, border, blur) from `theme.window`. Needs the window on screen for the blur.
    func applyGlass(_ theme: Theme) {
        let radius = GlassProbe.current == .noBlur ? 0 : theme.window.blurRadius
        let blur = WindowGlass.apply(blurRadius: radius, to: self)
        content.apply(theme.window, blur: blur)
        shadow.restyle(theme.window)
        if GlassProbe.current.paintsOwnShadow { shadow.attach(to: self) }
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
        glassDescription = "vidrio \(String(format: "%.2f", opacity)) · desenfoque \(blur.description)"
        describe()
    }

    private var glassDescription = ""

    /// "vidrio 0.62 · desenfoque 28", plus " · pantalla completa" while in full screen (tests tell it from zoom).
    private func describe() {
        setAccessibilityValue(glassDescription + (isFullScreen ? " · pantalla completa" : ""))
    }

    /// F4.5: square and borderless in full screen; the tokens again when it leaves.
    func showsFullScreenChrome(_ isFullScreen: Bool) {
        self.isFullScreen = isFullScreen
        if let tokens = paintedTokens { paint(tokens) }
        setAccessibilityHelp(isFullScreen ? "pantalla completa" : nil)
        describe()
    }

    private var isFullScreen = false
    private var paintedTokens: WindowTokens?
    /// Strip, pane grid and status bar trailing edges, in that order; the grid keeps its area padding.
    private var trailingEdges: [NSLayoutConstraint] = []
    private var areaPadding = 0.0
    private var sidePanel: NSView?

    func showSidePanel(_ panel: NSView?, width: Double) {
        sidePanel?.removeFromSuperview()
        sidePanel = panel
        for (edge, inset) in zip(trailingEdges, [width, width + areaPadding, width]) { edge.constant = -inset }
        guard let panel else { return }
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.widthAnchor.constraint(equalToConstant: width),
        ])
    }

    private func paint(_ tokens: WindowTokens) {
        paintedTokens = tokens
        layer?.cornerRadius = isFullScreen ? 0 : tokens.cornerRadius
        layer?.borderWidth = isFullScreen ? 0 : tokens.borderWidth
        layer?.borderColor = tokens.border.nsColor.cgColor
        layer?.backgroundColor = tokens.background.nsColor.cgColor
    }

    private func layoutChrome(theme: Theme) {
        let padding = theme.panel.areaPadding
        areaPadding = padding
        for view in [strip, paneGrid, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        trailingEdges = [
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneGrid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        NSLayoutConstraint.activate(trailingEdges)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.heightAnchor.constraint(equalToConstant: theme.chrome.topStripHeight),
            paneGrid.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: padding),
            paneGrid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            paneGrid.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -padding),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
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
