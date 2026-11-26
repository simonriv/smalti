import AppKit
import SmaltiCore

/// Preview runs as attributed text in the terminal's family, with `SmaltiSymbols` for the thin icons.
@MainActor
enum PromptRunText {
    static func attributed(_ lines: [[PreviewRun]], theme: Theme, size: Double? = nil) -> NSAttributedString {
        let pointSize = size ?? theme.promptStudio.previewFontSize
        let font =
            NSFont(name: theme.terminal.fontFamily, size: pointSize)
            ?? .monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let symbols = NSFontManager.shared.font(
            withFamily: symbolsFamily, traits: [], weight: regularWeight, size: pointSize)
        let text = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            for run in line {
                // The thin icons are private-use characters only `SmaltiSymbols` has.
                let isIcon = run.text.unicodeScalars.contains { iconRange.contains($0.value) }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: (isIcon ? symbols : nil) ?? font, .foregroundColor: run.color.nsColor,
                ]
                if let background = run.background { attributes[.backgroundColor] = background.nsColor }
                text.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        return text
    }

    /// `SmaltiSymbols`' code points (spec F5: U+E900–U+E91F).
    private static let iconRange: ClosedRange<UInt32> = 0xE900...0xE91F
    /// `NSFontManager`'s weight scale: 5 is regular.
    private static let regularWeight = 5

    private static let symbolsFamily = "SmaltiSymbols"
}

/// A template card: a small preview of the template and its name (`Prompt.dc.html`).
@MainActor
final class TemplateCardView: PanelButtonView {
    let template: PromptTemplate
    private let preview = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")

    init(template: PromptTemplate) {
        self.template = template
        super.init(
            identifier: "smalti.studio.template.\(Self.name(of: template))", label: template.title(.current))
        let stack = NSStackView(views: [preview, name])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Sizes are the same in every theme (`PromptStudioTokens`); the colors come in `render`.
        let padding = Theme.obsidian.promptStudio.templatePadding
        stack.spacing = Theme.obsidian.promptStudio.templateGap
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),
        ])
    }

    /// `cleanLine` and so on, the identifiers tests use.
    private static func name(of template: PromptTemplate) -> String {
        switch template {
        case .cleanLine: "cleanLine"
        case .singleLine: "singleLine"
        case .pills: "pills"
        case .symbolOnly: "symbolOnly"
        }
    }

    func render(isSelected: Bool, theme: Theme) {
        let panel = theme.appearancePanel
        layer?.cornerRadius = panel.cardCornerRadius
        layer?.borderWidth = isSelected ? panel.cardSelectedBorderWidth : panel.cardBorderWidth
        layer?.borderColor = (isSelected ? panel.selectedCardBorder : panel.cardBorder).nsColor.cgColor
        layer?.backgroundColor = isSelected ? panel.selectedCardBackground.nsColor.cgColor : nil
        preview.attributedStringValue = PromptRunText.attributed(
            Self.sample(template, theme: theme), theme: theme, size: theme.promptStudio.templateFontSize)
        let title = NSMutableAttributedString(
            string: template.title(.current),
            attributes: [
                .font: theme.interfaceFont(size: panel.rowFontSize, weight: 500),
                .foregroundColor: (isSelected ? panel.title : panel.text).nsColor,
            ])
        if let note = template.note(.current) {
            title.append(
                NSAttributedString(
                    string: " " + note,
                    attributes: [
                        .font: theme.interfaceFont(size: panel.rowFontSize), .foregroundColor: panel.secondary.nsColor,
                    ]))
        }
        name.attributedStringValue = title
        showSelected(isSelected)
    }

    /// The board's sample: a repository, its branch and a Node version, without icons.
    private static func sample(_ template: PromptTemplate, theme: Theme) -> [[PreviewRun]] {
        var config = PromptConfig.standard.applying(template)
        config.icons = .none
        config.modules = [.directory, .gitBranch, .runtime]
        var context = PromptContext(directory: "/Users/you/dev/solen", home: "/Users/you", copy: .current)
        context.repoRoot = "/Users/you/dev/solen"
        context.branch = "main"
        context.runtime = RuntimeVersion(kind: .node, version: "22.11")
        return PromptPreview.lines(config, context: context, theme: theme)
    }
}

/// A module row: drag handle, name with its note, and the checkbox; drags and ⌘↑ ⌘↓ move it among the active ones.
@MainActor
final class ModuleRowView: NSView {
    var onToggle: (() -> Void)?
    var onMove: ((Int) -> Void)?
    private let row: ModuleRow
    private let check: NSButton
    var module: PromptModuleID { row.id }
    private var dragStart: CGFloat?

    private let rowGap: Double

    init(row: ModuleRow, theme: Theme) {
        self.row = row
        rowGap = theme.promptStudio.moduleRowGap
        check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        super.init(frame: .zero)
        let tokens = theme.promptStudio
        let panel = theme.appearancePanel
        wantsLayer = true
        layer?.cornerRadius = tokens.moduleRowCornerRadius
        layer?.backgroundColor = row.isActive ? tokens.activeRow.nsColor.cgColor : nil
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("smalti.studio.module")
        setAccessibilityLabel(row.id.title(.current))
        let handle = NSTextField(labelWithString: "⋮⋮")
        handle.textColor = tokens.handle.nsColor
        handle.font = theme.interfaceFont(size: panel.rowFontSize)
        let name = NSTextField(labelWithAttributedString: Self.title(row, theme: theme))
        name.lineBreakMode = .byTruncatingTail
        check.state = row.isActive ? .on : .off
        check.target = self
        check.action = #selector(toggled)
        check.setAccessibilityIdentifier("smalti.studio.module.\(row.id.rawValue).toggle")
        let stack = NSStackView(views: [handle, name, NSView(), check])
        stack.orientation = .horizontal
        stack.spacing = tokens.moduleRowInnerGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: tokens.moduleRowHeight),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.moduleRowPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.moduleRowPadding),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private static func title(_ row: ModuleRow, theme: Theme) -> NSAttributedString {
        let panel = theme.appearancePanel
        let text = NSMutableAttributedString(
            string: row.id.title(.current),
            attributes: [
                .font: theme.interfaceFont(size: panel.rowFontSize),
                .foregroundColor: (row.isActive ? panel.text : panel.muted).nsColor,
            ])
        if row.isActive, let detail = row.id.detail(.current) {
            text.append(
                NSAttributedString(
                    string: " · " + detail,
                    attributes: [
                        .font: theme.interfaceFont(size: panel.rowFontSize), .foregroundColor: panel.secondary.nsColor,
                    ]))
        }
        return text
    }

    override var acceptsFirstResponder: Bool { true }
    /// A drag on it reorders; it never moves the window (transparent views do by default).
    override var mouseDownCanMoveWindow: Bool { false }

    /// The whole row takes the drag but the checkbox keeps its clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === check || hit.isDescendant(of: check) ? hit : self
    }

    @objc private func toggled() { onToggle?() }

    /// Pressed (VoiceOver, keyboard access) it takes the focus, so ⌘↑ and ⌘↓ move it.
    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = event.locationInWindow.y
    }

    /// Rows go down the screen as y goes down: a drag of one row's pitch moves it one place.
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let start = dragStart, row.isActive else { return }
        let pitch = bounds.height + rowGap
        let places = Int(((start - event.locationInWindow.y) / pitch).rounded())
        if places != 0 { onMove?(places) }
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), row.isActive else { return super.keyDown(with: event) }
        switch event.specialKey {
        case .upArrow?: onMove?(-1)
        case .downArrow?: onMove?(1)
        default: super.keyDown(with: event)
        }
    }
}
