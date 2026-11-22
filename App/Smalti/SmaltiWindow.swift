import AppKit
import SmaltiCore

/// Borderless-looking glass window: no traffic lights, rounded, dragged from the top strip.
final class SmaltiWindow: NSWindow {
    /// Window size of the approved design boards (docs/design/README.md).
    static let defaultContentSize = NSSize(width: 1328, height: 820)
    static let minimumContentSize = NSSize(width: 480, height: 300)

    let paneGrid: PaneGridView

    init(theme: Theme) {
        let content = WindowContentView(theme: theme)
        paneGrid = content.paneGrid
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // AppComposition owns the window; AppKit must not release it again on close.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentMinSize = Self.minimumContentSize
        contentView = content
        setContentSize(Self.defaultContentSize)
        setAccessibilityIdentifier("smalti.window")
        center()
    }
}

/// Rounded glass surface holding the drag strip and the pane area.
final class WindowContentView: NSView {
    let paneGrid: PaneGridView

    init(theme: Theme) {
        paneGrid = PaneGridView(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.window.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = theme.window.borderWidth
        layer?.borderColor = theme.window.border.nsColor.cgColor
        layer?.backgroundColor = theme.window.background.nsColor.cgColor
        layout(strip: DragStripView(), theme: theme)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }

    private func layout(strip: DragStripView, theme: Theme) {
        let padding = theme.panel.areaPadding
        for view in [strip, paneGrid] as [NSView] {
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
            paneGrid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
    }
}
