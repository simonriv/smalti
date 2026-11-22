import AppKit
import SmaltiCore

/// What a pane header shows: the foreground process (or the title), the abbreviated directory and the shortcut.
struct PaneHeader: Equatable {
    let process: String
    let directory: String
    let shortcut: String

    /// `⌘1`…`⌘9` from the keymap (the boards' `⌥1` is replaced: ⌥ types characters on the Latin American layout).
    init(_ pane: Pane, index: Int?, state: TilingState) {
        process = pane.headerName
        directory = pane.workingDirectory.abbreviated(home: state.home)
        shortcut = index.flatMap { state.config.keys.chord(for: .paneFocus($0))?.display } ?? ""
    }
}

/// Pane header (30 pt, Inter 11.5): neutral dot (F2 colors it), process in the title color, directory, shortcut.
@MainActor
final class PaneHeaderView: NSView {
    private var dot: StatusDot
    private let process = NSTextField(labelWithString: "")
    private let directory = NSTextField(labelWithString: "")
    private let shortcut: KbdView
    private let row = NSStackView()
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        dot = StatusDot(diameter: theme.header.dotSize, color: theme.strip.dot)
        shortcut = KbdView("", theme: theme)
        super.init(frame: .zero)
        directory.lineBreakMode = .byTruncatingHead
        directory.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        row.setViews([dot, process, directory, spacer, shortcut], in: .leading)
        row.spacing = theme.header.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.header.padding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.header.padding),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.paneHeader")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(_ header: PaneHeader, theme: Theme) {
        self.theme = theme
        let size = theme.header.fontSize
        process.font = theme.interfaceFont(size: size, weight: theme.header.processFontWeight)
        process.textColor = theme.text.title.nsColor
        process.stringValue = header.process
        directory.font = theme.interfaceFont(size: size)
        directory.textColor = theme.header.directory.nsColor
        directory.stringValue = header.directory
        shortcut.text = header.shortcut
        setAccessibilityLabel(header.process)
        setAccessibilityValue(header.directory)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.header.bottomBorder.nsColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: theme.panel.borderWidth).fill()
    }
}
