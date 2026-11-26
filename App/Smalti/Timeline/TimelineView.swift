import AppKit
import SmaltiCore

/// F9's panel (`docs/specs/F9-assets/mockup.html`): a 480 pt card on the right of the panes with the header and its
/// two chips, the session line or the search field, the list (rows, hits or recent sessions) and the key footer.
@MainActor
final class TimelineView: NSView, NSTextFieldDelegate {
    enum Key: Equatable {
        case up, down, left, right, open, close
        case text(String)
    }

    private let theme: Theme
    private let header: TimelineHeader
    private let top = NSStackView()
    private let field = NSTextField()
    /// Built once: rebuilding the search box on every paint would take the keyboard from its field.
    private lazy var searchBox = TimelineParts.searchBox(field, theme: theme)
    private let scope = TimelineScope()
    private let list: TimelineListView
    private let footer: TimelineFooter
    var onKey: ((Key) -> Void)?
    var onCopy: (() -> Void)?
    var onQuery: ((String) -> Void)?
    var onChoose: ((Int) -> Void)? {
        get { list.onChoose }
        set { list.onChoose = newValue }
    }

    override var acceptsFirstResponder: Bool { true }

    init(theme: Theme) {
        self.theme = theme
        header = TimelineHeader(theme: theme)
        list = TimelineListView(theme: theme)
        footer = TimelineFooter(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        let tokens = theme.timeline
        layer?.cornerRadius = tokens.radius
        layer?.backgroundColor = tokens.surface.nsColor.cgColor
        layer?.borderColor = tokens.border.nsColor.cgColor
        layer?.borderWidth = theme.chrome.hairlineWidth
        shadow = NSShadow()
        layer?.shadowOpacity = Float(tokens.shadowOpacity)
        layer?.shadowRadius = 25
        layer?.shadowOffset = CGSize(width: -18, height: 0)
        configureField()
        layoutAll()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Timeline"))
        setAccessibilityIdentifier("smalti.timeline")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func configureField() {
        let tokens = theme.timeline
        field.font = theme.interfaceFont(size: theme.processes.filterFontSize)
        field.textColor = theme.text.title.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = String(localized: "search this project")
        field.delegate = self
        field.setAccessibilityIdentifier("smalti.timeline.search.field")
        field.heightAnchor.constraint(equalToConstant: tokens.searchFieldHeight).isActive = true
    }

    private func layoutAll() {
        let tokens = theme.timeline
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 6
        top.edgeInsets = NSEdgeInsets(top: 9, left: tokens.padding, bottom: 9, right: tokens.padding)
        let views: [NSView] = [
            header, ProcessesView.hairline(theme.strip.bottomBorder), top,
            ProcessesView.hairline(theme.strip.bottomBorder),
            list, ProcessesView.hairline(theme.strip.bottomBorder), footer,
        ]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for hairline in views where hairline is NSBox {
            hairline.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        }
        list.setContentHuggingPriority(.init(1), for: .vertical)
        list.setContentCompressionResistancePriority(.init(1), for: .vertical)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: tokens.headerHeight),
            footer.heightAnchor.constraint(equalToConstant: tokens.footerHeight),
        ])
    }

    // MARK: - Showing

    func show(_ screen: TimelineScreen) {
        header.show(mode: screen.mode)
        footer.show(keys: screen.keys)
        // The search box and its scope line stay in place while searching (the field keeps the keyboard).
        let keepsSearch = screen.mode == .search && top.arrangedSubviews.first === searchBox
        if keepsSearch, case .search(_, let scopeName, let root, let summary, _) = screen.body {
            scope.show(scopeName, root: root, summary: summary, theme: theme)
            top.isHidden = false
            list.show(screen)
            return
        }
        top.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch screen.body {
        case .session(let info, let banner, _):
            if let banner { top.addArrangedSubview(TimelineParts.banner(banner, theme: theme)) }
            TimelineParts.session(info, theme: theme).forEach(top.addArrangedSubview)
        case .search(_, let scopeName, let root, let summary, _):
            top.addArrangedSubview(searchBox)
            scope.show(scopeName, root: root, summary: summary, theme: theme)
            top.addArrangedSubview(scope)
        case .loading, .failed, .empty: break
        }
        top.isHidden = top.arrangedSubviews.isEmpty
        list.show(screen)
    }

    func setQuery(_ text: String) {
        field.stringValue = text
        focusSearch()
        field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    func focusSearch() {
        window?.makeFirstResponder(field)
    }

    func showNotice(_ text: String?, isFailure: Bool) {
        footer.showNotice(text, isFailure: isFailure)
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(for: event) else { return super.keyDown(with: event) }
        onKey?(key)
    }

    /// ⌘C on the timeline (the panel or its search field has the keyboard) copies the chosen item whole: the
    /// terminal's ⌘C passes through while the timeline is open, and Smalti's Edit menu acts by closures, not `copy:`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCopy =
            event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "c"
        guard isCopy, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        onCopy?()
        return true
    }

    private static let escapeKeyCode: UInt16 = 53

    private static func key(for event: NSEvent) -> Key? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.specialKey {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .carriageReturn, .enter: return .open
        default: break
        }
        if event.keyCode == escapeKeyCode { return .close }
        guard event.specialKey == nil, let characters = event.characters, !characters.isEmpty,
            characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return .text(characters)
    }

    // MARK: - The search field

    func controlTextDidChange(_ notification: Notification) {
        onQuery?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let keys: [Selector: Key] = [
            #selector(moveUp(_:)): .up, #selector(moveDown(_:)): .down, #selector(insertNewline(_:)): .open,
            #selector(cancelOperation(_:)): .close,
        ]
        guard let key = keys[selector] else { return false }
        onKey?(key)
        return true
    }
}

/// "Timeline", the two chips with their chords and esc.
@MainActor
private final class TimelineHeader: NSView {
    private let session: TimelineChip
    private let search: TimelineChip

    init(theme: Theme) {
        session = TimelineChip(
            String(localized: "Session"), keys: "⇧⌘T", theme: theme, identifier: "smalti.timeline.chip.session")
        search = TimelineChip(
            String(localized: "Search"), keys: "⌘F", theme: theme, identifier: "smalti.timeline.chip.search")
        super.init(frame: .zero)
        let title = ObservatoryText.label(
            String(localized: "Timeline"),
            .init(size: theme.observatory.stripTitleSize, color: theme.text.title, weight: 600),
            theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [title, spacer, session, search, KbdView("esc", theme: theme)])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: theme.timeline.padding, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(mode: TimelineScreen.Mode) {
        session.isOn = mode == .session
        search.isOn = mode == .search
    }
}

/// A header chip: the accent's ring and glow when it is the view shown. Not a button: its chord is the way in.
@MainActor
private final class TimelineChip: NSView {
    private let theme: Theme
    private let title: NSTextField

    init(_ text: String, keys: String, theme: Theme, identifier: String) {
        self.theme = theme
        let chips = theme.observatoryFilter
        title = ObservatoryText.label(
            text,
            .init(
                size: theme.observatory.pillFontSize, color: chips.inactiveText, weight: theme.observatory.pillWeight),
            theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = chips.chipRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        let stack = NSStackView(views: [title, KbdView(keys, theme: theme)])
        stack.spacing = theme.processes.footerKeyGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: theme.timeline.toolRowHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
        setAccessibilityIdentifier(identifier)
        isOn = false
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    var isOn: Bool = false {
        didSet {
            let chips = theme.observatoryFilter
            layer?.borderColor =
                (isOn ? theme.focus.ring : RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)).nsColor.cgColor
            layer?.backgroundColor =
                (isOn ? theme.focus.glow : RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)).nsColor.cgColor
            title.textColor = (isOn ? chips.chosenText : chips.inactiveText).nsColor
            setAccessibilityValue(isOn ? "selected" : "")
        }
    }
}

/// The key hints, and a notice on the right for 4 s.
@MainActor
private final class TimelineFooter: NSView {
    private let theme: Theme
    private let keys = NSStackView()
    private let notice: NSTextField

    init(theme: Theme) {
        self.theme = theme
        notice = ObservatoryText.label("", .init(size: 11, color: theme.text.primary), theme: theme)
        super.init(frame: .zero)
        notice.setAccessibilityIdentifier("smalti.timeline.notice")
        notice.lineBreakMode = .byTruncatingHead
        notice.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        keys.spacing = 10
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [keys, spacer, notice])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: theme.timeline.padding, bottom: 0, right: theme.timeline.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func show(keys hints: [(key: String, label: String)]) {
        keys.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for hint in hints {
            let label = ObservatoryText.label(hint.label, .init(size: 11, color: theme.text.secondary), theme: theme)
            let pair = NSStackView(views: [KbdView(hint.key, theme: theme), label])
            pair.spacing = 5
            keys.addArrangedSubview(pair)
        }
    }

    func showNotice(_ text: String?, isFailure: Bool) {
        notice.stringValue = text ?? ""
        notice.textColor = (isFailure ? theme.timeline.failure : theme.text.primary).nsColor
    }
}

/// "Proyecto · <name>", the root and the summary of the search: one view whose texts change as results come.
@MainActor
private final class TimelineScope: NSView {
    private var content: NSView?

    func show(_ scope: String, root: String, summary: String, theme: Theme) {
        content?.removeFromSuperview()
        let line = TimelineParts.scope(scope, root: root, summary: summary, theme: theme)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        content = line
    }
}
