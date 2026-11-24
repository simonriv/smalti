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
    /// The row the list keeps in view while its frames settle; only the latest one counts.
    private weak var revealedRow: NSView?
    /// Under the list; hidden with it so the field and the footer never show a doubled line.
    private let listSeparator = NSView()
    private var navigateHint: NSView?

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: makeContent(), theme: theme)
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

    /// Scrolls the list just enough to show `row` whole, with its group label when it opens a group. The window of
    /// built rows counts rows only, while group labels take height too, so the selection can sit below the clipped
    /// edge without this. Rows were just rebuilt and their frames settle in later layout passes, so the row is kept
    /// and shown again whenever the list changes size, until another row is revealed.
    func reveal(_ row: NSView) {
        revealedRow = row
        showRevealedRow()
        DispatchQueue.main.async { [weak self] in self?.showRevealedRow() }
    }

    private func showRevealedRow() {
        // The rows may have been replaced (rename mode); a detached row has no frame to show.
        guard let row = revealedRow, let document = scroll.documentView, row.isDescendant(of: document) else { return }
        window?.layoutIfNeeded()
        // The first row needs no frame at all: the list goes back to its top. Right after a wrap from the last row,
        // the rebuilt stack's frames can still be one row off, and that row would hide the top again.
        if opensTheList(row) {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        var target = row.convert(row.bounds, to: document)
        if let label = groupLabel(above: row) { target = target.union(label.convert(label.bounds, to: document)) }
        scroll.contentView.scrollToVisible(target)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func opensTheList(_ row: NSView) -> Bool {
        let views = list.arrangedSubviews
        return views.first === row || (views.first is CommandGroupLabel && views.dropFirst().first === row)
    }

    private func groupLabel(above row: NSView) -> NSView? {
        let views = list.arrangedSubviews
        guard let index = views.firstIndex(of: row), index > 0 else { return nil }
        return views[index - 1] is CommandGroupLabel ? views[index - 1] : nil
    }

    /// The rename prompt has nothing to navigate; only "↵ ejecutar" applies.
    func showNavigationHint(_ isShown: Bool) {
        navigateHint?.isHidden = !isShown
    }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        let stack = NSStackView(views: [fieldRow(), separator(), listArea(), separator(listSeparator), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        return stack
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
        document.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: document, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showRevealedRow() }
        }
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        pin(list, to: document)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.setAccessibilityIdentifier("smalti.palette.list")
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
        OverlayBox.hint(keys, action, theme: theme)
    }

    private func footerLabel(_ text: String) -> NSTextField {
        OverlayBox.footerLabel(text, theme: theme)
    }

    private func separator(_ line: NSView = NSView()) -> NSView {
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.palette.footerBorder.nsColor.cgColor
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    private func pin(_ view: NSView, to container: NSView) {
        OverlayBox.pin(view, to: container)
    }
}

/// Lays the row list out top-down inside the scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The palette's text field. Smalti has no Edit menu (the terminal owns ⌘C/⌘V), so the editing shortcuts are
/// handled here: ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z go to the field editor.
final class PaletteField: NSTextField {
    private struct Shortcut: Hashable {
        let key: String
        let isShifted: Bool
    }

    private static let editActions: [Shortcut: Selector] = [
        Shortcut(key: "a", isShifted: false): #selector(NSResponder.selectAll(_:)),
        Shortcut(key: "c", isShifted: false): #selector(NSText.copy(_:)),
        Shortcut(key: "v", isShifted: false): #selector(NSText.paste(_:)),
        Shortcut(key: "x", isShifted: false): #selector(NSText.cut(_:)),
        Shortcut(key: "z", isShifted: false): undo,
        Shortcut(key: "z", isShifted: true): redo,
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let editor = currentEditor(), flags.subtracting(.shift) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased(),
            let action = Self.editActions[Shortcut(key: key, isShifted: flags.contains(.shift))]
        else { return super.performKeyEquivalent(with: event) }
        // Undo and redo live on the window's undo manager, up the responder chain from the field editor.
        let isHistory = action == Self.undo || action == Self.redo
        return NSApp.sendAction(action, to: isHistory ? nil : editor, from: self)
    }

    private static let undo = Selector(("undo:"))
    private static let redo = Selector(("redo:"))

    /// The shared field editor does not record undo by default.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.allowsUndo = true
        return accepted
    }
}
