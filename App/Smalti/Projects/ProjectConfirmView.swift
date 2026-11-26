import AppKit
import SmaltiCore

/// F8.5: "¿Abrir el proyecto “…”?" and "Guardar layout del proyecto" (mockup `confirm`, `changed`, `replace`): the ⌘K
/// glass with the amber border and dot of "te espera", the commands in mono with what changed, the note and the keys.
/// ↩ confirms, esc cancels; the words come from the domain (`ProjectCard`).
@MainActor
final class ProjectConfirmView: NSView {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    private let theme: Theme

    init(_ card: ProjectCardContent, theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: content(card), theme: theme, border: theme.projects.confirmBorder)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(card.title)
        setAccessibilityIdentifier("smalti.projects.confirm")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    /// Key codes, the same on every layout.
    private enum Key {
        static let returns: Set<UInt16> = [36, 76]
        static let escape: UInt16 = 53
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        // Review 2: a held ↩ auto-repeats into the card from ⌘K or ⌘O; only a fresh press confirms.
        case let code where Key.returns.contains(code):
            if ConfirmationKey.confirms(isRepeat: event.isARepeat) { onConfirm?() }
        case Key.escape: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    private func content(_ card: ProjectCardContent) -> NSView {
        let tokens = theme.projects
        var views: [NSView] = [heading(card), commands(card.lines)]
        if let extra = card.extra { views.append(label(extra, color: theme.text.primary, size: tokens.noteFontSize)) }
        views.append(label(card.note, color: theme.text.secondary, size: tokens.noteFontSize))
        let body = NSStackView(views: views)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = tokens.lineGap
        body.edgeInsets = NSEdgeInsets(
            top: tokens.padding, left: tokens.padding, bottom: tokens.padding, right: tokens.padding)
        views.forEach {
            $0.widthAnchor.constraint(equalToConstant: tokens.confirmWidth - 2 * tokens.padding).isActive = true
        }
        let stack = NSStackView(views: [body, OverlayBox.separator(theme: theme), footer(card)])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        return stack
    }

    private func heading(_ card: ProjectCardContent) -> NSView {
        let tokens = theme.projects
        let dot = StatusDot(diameter: theme.header.dotSize, style: .filled(theme.agent.waiting))
        let title = NSTextField(labelWithString: card.title)
        title.font = theme.interfaceFont(size: tokens.titleFontSize, weight: 600)
        title.textColor = theme.text.title.nsColor
        title.setAccessibilityIdentifier("smalti.projects.title")
        let line = NSStackView(views: [dot, title])
        line.spacing = tokens.dotGap
        let body = label(card.body, color: theme.text.secondary, size: tokens.bodyFontSize)
        let stack = NSStackView(views: [line, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.headingGap
        return stack
    }

    private func commands(_ lines: [ProjectCardLine]) -> NSView {
        let tokens = theme.projects
        let box = NSStackView(views: lines.map(commandRow))
        box.orientation = .vertical
        box.alignment = .width
        box.spacing = 0
        box.edgeInsets = NSEdgeInsets(
            top: tokens.commandsPadding, left: 0, bottom: tokens.commandsPadding, right: 0)
        box.wantsLayer = true
        box.layer?.cornerRadius = tokens.commandsRadius
        box.layer?.backgroundColor = tokens.commandsBackground.nsColor.cgColor
        box.layer?.borderWidth = theme.chrome.hairlineWidth
        box.layer?.borderColor = theme.palette.footerBorder.nsColor.cgColor
        box.setAccessibilityIdentifier("smalti.projects.commands")
        return box
    }

    private func commandRow(_ line: ProjectCardLine) -> NSView {
        let tokens = theme.projects
        let font = theme.monospacedFont(size: tokens.commandFontSize)
        let sign = NSTextField(labelWithString: line.sign)
        sign.font = font
        sign.textColor = signColor(line.kind).nsColor
        sign.widthAnchor.constraint(equalToConstant: tokens.signWidth).isActive = true
        let command = NSTextField(labelWithAttributedString: commandText(line, font: font))
        command.lineBreakMode = .byTruncatingTail
        command.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let place = NSTextField(labelWithString: line.place ?? "")
        place.font = theme.monospacedFont(size: tokens.noteFontSize)
        place.textColor = theme.text.secondary.nsColor
        let row = NSStackView(views: [sign, command, spacer, place])
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 0, left: tokens.commandRowInset, bottom: 0, right: tokens.commandRowInset)
        row.heightAnchor.constraint(equalToConstant: tokens.commandRowHeight).isActive = true
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        row.setAccessibilityIdentifier("smalti.projects.command")
        row.setAccessibilityLabel([line.command, line.place].compactMap { $0 }.joined(separator: " · "))
        row.setAccessibilityValue(line.kind.rawValue)
        return row
    }

    private func commandText(_ line: ProjectCardLine, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        switch line.kind {
        case .added: attributes[.foregroundColor] = theme.agent.working.nsColor
        case .removed:
            attributes[.foregroundColor] = theme.text.secondary.nsColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = theme.projects.removedStrike.nsColor
        case .same: attributes[.foregroundColor] = theme.text.primary.nsColor
        }
        return NSAttributedString(string: line.command, attributes: attributes)
    }

    private func signColor(_ kind: ProjectCommandLine.Kind) -> RGBAColor {
        switch kind {
        case .added: theme.agent.working
        case .removed: theme.agent.failed
        case .same: theme.text.secondary
        }
    }

    private func label(_ text: String, color: RGBAColor, size: Double) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = theme.interfaceFont(size: size)
        label.textColor = color.nsColor
        label.preferredMaxLayoutWidth = theme.projects.confirmWidth - 2 * theme.projects.padding
        return label
    }

    private func footer(_ card: ProjectCardContent) -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [
            OverlayBox.hint("↵", card.confirmLabel, theme: theme),
            OverlayBox.hint("esc", card.cancelLabel, theme: theme),
            spacer,
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }
}
