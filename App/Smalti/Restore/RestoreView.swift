import AppKit
import SmaltiCore

/// "Retomar donde quedaste" (Reanudar.dc.html, left column; the session list on the right is F6). Draws what the
/// controller says and reports keys and clicks; it decides nothing.
final class RestoreView: NSView {
    struct State {
        let checked: Set<UUID>
        let highlighted: UUID?
        let restoreCount: Int
        let alwaysRestore: Bool
    }

    var onKey: ((RestoreKey) -> Bool)?
    var onToggleRow: ((UUID) -> Void)?
    var onAction: ((RestoreController.Action) -> Void)?

    private let theme: Theme
    private var rows: [RestoreRowView] = []
    private let primary: ResumeButton
    private let layoutsOnly: ResumeButton
    private let startClean: ResumeButton
    private let always = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(theme: Theme, workspaces: [ResumeWorkspace], closedAt: String) {
        self.theme = theme
        primary = ResumeButton(style: .primary, theme: theme, identifier: "restore.primary")
        layoutsOnly = ResumeButton(style: .secondary, theme: theme, identifier: "restore.layoutsOnly")
        startClean = ResumeButton(style: .tertiary, theme: theme, identifier: "restore.startClean")
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.restore")
        layoutsOnly.title = "Solo layouts"
        startClean.title = "Empezar limpio"
        primary.onClick = { [weak self] in self?.onAction?(.restore) }
        layoutsOnly.onClick = { [weak self] in self?.onAction?(.layoutsOnly) }
        startClean.onClick = { [weak self] in self?.onAction?(.startClean) }
        always.target = self
        always.action = #selector(alwaysToggled)
        always.contentTintColor = theme.accent.nsColor
        always.setAccessibilityIdentifier("restore.always")
        build(workspaces: workspaces, closedAt: closedAt)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let key = RestoreKey(event), onKey?(key) == true else { return super.keyDown(with: event) }
    }

    /// ⌘L and ⌘, act wherever the focus is inside the screen (a button, with full keyboard access).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden, window != nil, let key = RestoreKey(event) else { return false }
        return onKey?(key) == true
    }

    func render(_ state: State) {
        for row in rows {
            row.render(isChecked: state.checked.contains(row.id), isHighlighted: row.id == state.highlighted)
        }
        primary.title = "Restaurar \(state.restoreCount) \(state.restoreCount == 1 ? "panel" : "paneles")"
        always.state = state.alwaysRestore ? .on : .off
    }

    @objc private func alwaysToggled() {
        onAction?(.toggleAlways)
    }

    // MARK: - Layout

    private func build(workspaces: [ResumeWorkspace], closedAt: String) {
        let tokens = theme.resume
        let header = NSStackView(views: [
            label(
                "Retomar donde quedaste", size: tokens.titleFontSize, weight: tokens.titleWeight,
                color: theme.text.title),
            wrapping(
                "Cerraste \(closedAt). Los shells vuelven con su historial y salida; los agentes se relanzan con su "
                    + "propio comando de reanudación.", size: tokens.subtitleFontSize, color: tokens.subtitleText),
        ])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = tokens.titleGap
        let sections = workspaces.map(section)
        let list = NSStackView(views: sections)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = tokens.blockGap
        sections.forEach { $0.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = FlippedClip(list)
        let column = NSStackView(views: [header, scroll, footer()])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = tokens.blockGap
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let width = column.widthAnchor.constraint(equalToConstant: tokens.contentWidth - 2 * tokens.paddingHorizontal)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor), width,
            column.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * tokens.paddingHorizontal),
            column.topAnchor.constraint(equalTo: topAnchor, constant: tokens.paddingVertical),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -tokens.paddingVertical),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
    }

    private func section(_ workspace: ResumeWorkspace) -> NSView {
        let tokens = theme.resume
        let dot = StatusDot(diameter: theme.header.dotSize, style: theme.statusDot(for: workspace.status))
        let heading = NSStackView(views: [
            dot,
            label(
                workspace.name, size: tokens.workspaceFontSize, weight: tokens.workspaceWeight, color: theme.text.title),
            label(workspace.summary, size: tokens.summaryFontSize, color: theme.text.secondary),
        ])
        heading.spacing = tokens.headerGap
        let padding = tokens.headerPadding
        heading.edgeInsets = NSEdgeInsets(
            top: padding.top, left: padding.horizontal, bottom: padding.bottom, right: padding.horizontal)
        let rowViews = workspace.rows.map { row in
            let view = RestoreRowView(row, theme: theme)
            view.onToggle = { [weak self] in self?.onToggleRow?(row.id) }
            return view
        }
        rows += rowViews
        let stack = NSStackView(views: [heading] + rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.sectionRowGap
        let inset = tokens.sectionPadding
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        rowViews.forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * inset).isActive = true
        }
        stack.wantsLayer = true
        stack.layer?.cornerRadius = theme.panel.cornerRadius
        stack.layer?.backgroundColor = theme.panel.background.nsColor.cgColor
        stack.layer?.borderColor = theme.panel.border.nsColor.cgColor
        stack.layer?.borderWidth = theme.panel.borderWidth
        return stack
    }

    private func footer() -> NSView {
        let tokens = theme.resume
        let hint = label("Siempre restaurar", size: tokens.hintFontSize, color: theme.text.secondary)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [
            primary, layoutsOnly, startClean, spacer, always, hint, KbdView("⌘,", theme: theme),
        ])
        stack.spacing = tokens.buttonGap
        stack.setCustomSpacing(tokens.hintGap, after: always)
        stack.setCustomSpacing(tokens.hintGap, after: hint)
        return stack
    }

    private func label(_ text: String, size: Double, weight: Int = 400, color: RGBAColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = theme.interfaceFont(size: size, weight: weight)
        field.textColor = color.nsColor
        return field
    }

    private func wrapping(_ text: String, size: Double, color: RGBAColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = theme.interfaceFont(size: size)
        field.textColor = color.nsColor
        return field
    }
}

/// Puts the section list at the top of its scroll view.
private final class FlippedClip: NSView {
    init(_ content: NSView) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
}

/// The resume screen's three buttons (Reanudar.dc.html): accent, outlined and text-only.
final class ResumeButton: NSButton {
    enum Style { case primary, secondary, tertiary }

    var onClick: (() -> Void)?
    private let style: Style
    private let theme: Theme

    init(style: Style, theme: Theme, identifier: String) {
        self.style = style
        self.theme = theme
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = theme.resume.buttonCornerRadius
        target = self
        action = #selector(clicked)
        setAccessibilityIdentifier(identifier)
        heightAnchor.constraint(equalToConstant: theme.resume.buttonHeight).isActive = true
        switch style {
        case .primary: layer?.backgroundColor = theme.accent.nsColor.cgColor
        case .secondary:
            layer?.borderWidth = theme.resume.buttonBorderWidth
            layer?.borderColor = theme.resume.secondaryButtonBorder.nsColor.cgColor
        case .tertiary: break
        }
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var title: String {
        didSet {
            let tokens = theme.resume
            let color: RGBAColor =
                switch style {
                case .primary: tokens.primaryButtonText
                case .secondary: theme.text.primary
                case .tertiary: tokens.tertiaryButtonText
                }
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: theme.interfaceFont(
                        size: tokens.buttonFontSize,
                        weight: style == .primary ? tokens.primaryButtonWeight : tokens.buttonWeight),
                    .foregroundColor: color.nsColor,
                ])
            setAccessibilityLabel(title)
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 2 * theme.resume.buttonPaddingHorizontal, height: theme.resume.buttonHeight)
    }

    @objc private func clicked() {
        onClick?()
    }
}
