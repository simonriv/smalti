import AppKit
import SmaltiCore

/// The ⌘K panel of Paleta.dc.html: 640 pt wide, 110 pt below the top of the window, glass with a 36 pt blur,
/// a 52 pt search field, grouped rows and a 36 pt footer. It draws; `CommandPaletteController` decides.
@MainActor
final class CommandPaletteView: NSView {
    let field = PaletteField()
    private let theme: Theme
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private var scrollHeight: NSLayoutConstraint?
    /// Under the list; hidden with it so the field and the footer never show a doubled line.
    private let listSeparator = NSView()
    private var navigateHint: NSView?

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        let content = makeContent()
        layoutBox(content)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.palette")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Rows and group labels in display order; the list grows with them up to `maximumListHeight`.
    func show(_ views: [NSView], maximumListHeight: Double) {
        list.setViews(views, in: .top)
        fitList(maximumHeight: maximumListHeight)
        scroll.isHidden = views.isEmpty
        listSeparator.isHidden = views.isEmpty
    }

    /// The list grows with its rows up to `maximumHeight` (recomputed when the window resizes).
    func fitList(maximumHeight: Double) {
        list.layoutSubtreeIfNeeded()
        scrollHeight?.constant = min(list.fittingSize.height, maximumHeight)
    }

    /// The rename prompt has nothing to navigate; only "↵ ejecutar" applies.
    func showNavigationHint(_ isShown: Bool) {
        navigateHint?.isHidden = !isShown
    }

    override func layout() {
        super.layout()
        let radius = theme.palette.cornerRadius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func scrollToVisible(_ view: NSView) {
        view.scrollToVisible(view.bounds)
    }

    // MARK: - Layout

    /// Shadow outside, blur and tint inside the rounded box, border on top.
    private func layoutBox(_ content: NSView) {
        let palette = theme.palette
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(palette.shadowOpacity)
        // CSS blur radius is twice the Core Animation shadow radius; y grows down in CSS and up here.
        layer?.shadowRadius = palette.shadowBlur / 2
        layer?.shadowOffset = CGSize(width: 0, height: -palette.shadowOffsetY)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = palette.cornerRadius
        blur.layer?.masksToBounds = true
        for view in [blur, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            pin(view, to: self)
        }
    }

    private func makeContent() -> NSView {
        let palette = theme.palette
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = palette.cornerRadius
        content.layer?.borderWidth = theme.chrome.hairlineWidth
        content.layer?.borderColor = palette.border.nsColor.cgColor
        content.layer?.backgroundColor = palette.background.nsColor.cgColor
        let stack = NSStackView(views: [fieldRow(), separator(), listArea(), separator(listSeparator), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        pin(stack, to: content)
        return content
    }

    private func fieldRow() -> NSView {
        let palette = theme.palette
        let icon = CommandIconView(CommandIcons.search, size: palette.iconSize, lineWidth: palette.searchIconStroke)
        icon.color = theme.text.secondary.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.interfaceFont(size: palette.fieldFontSize)
        field.textColor = theme.text.title.nsColor
        field.setAccessibilityLabel("Buscar comando")
        field.setAccessibilityIdentifier("smalti.paletteField")
        let row = NSStackView(views: [icon, field, KbdView("esc", theme: theme)])
        row.spacing = palette.fieldGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.fieldHeight).isActive = true
        return row
    }

    private func listArea() -> NSView {
        let palette = theme.palette
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(
            top: palette.listPaddingTop, left: palette.listPaddingHorizontal, bottom: palette.listPaddingBottom,
            right: palette.listPaddingHorizontal)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        pin(list, to: document)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        scrollHeight?.isActive = true
        return scroll
    }

    /// "↑↓ navegar · ↵ ejecutar" and the board's closing line. "⌘↵ en panel nuevo" is left out: no F1 command runs
    /// in a pane (deviation justified in the PR).
    private func footer() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let navigate = hint("↑↓", "navegar")
        navigateHint = navigate
        let row = NSStackView(views: [
            navigate, hint("↵", "ejecutar"), spacer,
            footerLabel("Todo lo que hacen los botones vive aquí"),
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }

    /// `<kbd>↑↓</kbd> navegar`: the board separates key and word with a plain space.
    private func hint(_ keys: String, _ action: String) -> NSView {
        let row = NSStackView(views: [KbdView(keys, theme: theme), footerLabel(" \(action)")])
        row.spacing = 0
        return row
    }

    private func footerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = theme.interfaceFont(size: theme.palette.footerFontSize)
        label.textColor = theme.text.secondary.nsColor
        return label
    }

    private func separator(_ line: NSView = NSView()) -> NSView {
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.palette.footerBorder.nsColor.cgColor
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    private func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// Lays the row list out top-down inside the scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The palette's text field. Smalti has no Edit menu (the terminal owns ⌘C/⌘V), so the editing shortcuts are
/// handled here: ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z go to the field editor.
final class PaletteField: NSTextField {
    private static let editActions: [String: Selector] = [
        "a": #selector(NSResponder.selectAll(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)), "z": Selector(("undo:")),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = currentEditor(), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased(), let action = Self.editActions[key]
        else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(action, to: editor, from: self)
    }
}
