import AppKit
import SmaltiCore

/// "Reportar un problema o una idea" (mockup-feedback.png): the ⌘K glass box with the two kinds, the logs box, the
/// build line and the keys. Every action has a key: ←→ kind, espacio logs, ↩ open, esc cancel.
@MainActor
final class FeedbackView: NSView {
    var onKind: ((FeedbackKind) -> Void)?
    var onToggleLogs: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    private let theme: Theme
    private let bug: FeedbackChoice
    private let idea: FeedbackChoice
    private let logs = NSButton(
        checkboxWithTitle: "Guardar los registros de esta sesión para adjuntarlos", target: nil, action: nil)

    init(theme: Theme, summary: String) {
        self.theme = theme
        bug = FeedbackChoice("Fallo", dot: theme.agent.failed, theme: theme)
        idea = FeedbackChoice("Idea", dot: theme.feedback.ideaDot, theme: theme)
        super.init(frame: .zero)
        OverlayBox.decorate(self, around: content(summary: summary), theme: theme)
        bug.onClick = { [weak self] in self?.onKind?(.bug) }
        idea.onClick = { [weak self] in self?.onKind?(.idea) }
        logs.target = self
        logs.action = #selector(logsClicked)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Reportar un problema o una idea")
        setAccessibilityIdentifier("smalti.feedback")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        OverlayBox.updateShadow(of: self, theme: theme)
    }

    func show(kind: FeedbackKind, includesLogs: Bool) {
        bug.setSelected(kind == .bug)
        idea.setSelected(kind == .idea)
        logs.state = includesLogs ? .on : .off
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onKind?(.bug)
        case 124: onKind?(.idea)
        case 49: onToggleLogs?()
        case 36, 76: onSubmit?()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    @objc private func logsClicked() {
        onToggleLogs?()
    }

    private func content(summary: String) -> NSView {
        let tokens = theme.feedback
        let title = NSTextField(labelWithString: "Reportar un problema o una idea")
        title.font = theme.interfaceFont(size: tokens.titleFontSize, weight: 600)
        title.textColor = theme.text.title.nsColor
        let choices = NSStackView(views: [bug, idea])
        choices.distribution = .fillEqually
        choices.spacing = tokens.choiceGap
        logs.font = theme.interfaceFont(size: theme.palette.rowFontSize - 0.5)
        logs.setAccessibilityIdentifier("smalti.feedbackLogs")
        let note = NSTextField(
            wrappingLabelWithString: "Se guardan en Descargas y se muestran en Finder; los arrastras tú al issue.")
        note.font = theme.interfaceFont(size: tokens.noteFontSize)
        note.textColor = theme.text.secondary.nsColor
        let build = NSTextField(labelWithString: summary)
        build.font = NSFont.monospacedSystemFont(ofSize: tokens.summaryFontSize, weight: .regular)
        build.textColor = theme.text.secondary.nsColor
        build.setAccessibilityIdentifier("smalti.feedbackBuild")
        // The note wraps inside the box and gives way first: on one line it would widen the box.
        note.preferredMaxLayoutWidth = tokens.width - 2 * tokens.padding
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let body = NSStackView(views: [title, choices, logs, note, build])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = tokens.choiceGap + 4
        body.translatesAutoresizingMaskIntoConstraints = false
        let padded = NSView()
        padded.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: padded.leadingAnchor, constant: tokens.padding),
            body.widthAnchor.constraint(equalToConstant: tokens.width - 2 * tokens.padding),
            body.topAnchor.constraint(equalTo: padded.topAnchor, constant: tokens.padding),
            body.bottomAnchor.constraint(equalTo: padded.bottomAnchor, constant: -tokens.padding),
            choices.widthAnchor.constraint(equalTo: body.widthAnchor),
            note.widthAnchor.constraint(equalTo: body.widthAnchor),
        ])
        let stack = NSStackView(views: [padded, OverlayBox.separator(theme: theme), footer()])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        return stack
    }

    private func footer() -> NSView {
        let palette = theme.palette
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let open = OverlayBox.hint("↩", "Abrir en GitHub", theme: theme)
        let row = NSStackView(views: [
            OverlayBox.hint("←→", "tipo", theme: theme), OverlayBox.hint("espacio", "registros", theme: theme), spacer,
            OverlayBox.hint("esc", "cancelar", theme: theme), open,
        ])
        row.spacing = palette.footerGap
        row.edgeInsets = NSEdgeInsets(top: 0, left: palette.fieldPadding, bottom: 0, right: palette.fieldPadding)
        row.heightAnchor.constraint(equalToConstant: palette.footerHeight).isActive = true
        return row
    }
}

/// "Fallo" / "Idea": a dot of the state's colour and the word, framed in the accent when chosen.
@MainActor
private final class FeedbackChoice: NSView {
    var onClick: (() -> Void)?
    private let theme: Theme

    init(_ title: String, dot color: RGBAColor, theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.palette.rowCornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        let dot = StatusDot(diameter: theme.header.dotSize, style: .filled(color))
        let label = NSTextField(labelWithString: title)
        label.font = theme.interfaceFont(size: theme.palette.rowFontSize)
        label.textColor = theme.text.title.nsColor
        let row = NSStackView(views: [dot, label])
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor), row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: theme.feedback.choiceHeight),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityIdentifier("smalti.feedback.\(title.lowercased())")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func setSelected(_ isSelected: Bool) {
        layer?.backgroundColor = isSelected ? theme.palette.selection.nsColor.cgColor : NSColor.clear.cgColor
        layer?.borderColor = (isSelected ? theme.focus.ring : theme.palette.border).nsColor.cgColor
        setAccessibilityValue(isSelected ? 1 : 0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
