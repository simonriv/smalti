import AppKit
import SmaltiCore

/// One pane on the resume screen (`.item` of Reanudar.dc.html): checkbox, tag, title with detail, code.
final class RestoreRowView: NSView {
    let id: UUID
    var onToggle: (() -> Void)?
    private let theme: Theme
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let tagView = TagView()
    private let title = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")

    init(_ row: ResumeRow, theme: Theme) {
        id = row.id
        self.theme = theme
        super.init(frame: .zero)
        let tokens = theme.resume
        wantsLayer = true
        layer?.cornerRadius = tokens.rowCornerRadius
        checkbox.contentTintColor = theme.accent.nsColor
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.setAccessibilityIdentifier("restore.row.\(row.id.uuidString)")
        checkbox.setAccessibilityLabel(row.title)
        tagView.configure(row.tag, theme: theme)
        title.attributedStringValue = Self.title(row, theme: theme)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        code.stringValue = row.code ?? ""
        code.font = theme.monospacedFont(size: tokens.codeFontSize)
        code.textColor = theme.text.secondary.nsColor
        let stack = NSStackView(views: [checkbox, tagView, title, code])
        stack.spacing = tokens.rowGap
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.rowPaddingVertical, left: tokens.rowPaddingHorizontal, bottom: tokens.rowPaddingVertical,
            right: tokens.rowPaddingHorizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: tokens.checkboxSize),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func render(isChecked: Bool, isHighlighted: Bool) {
        checkbox.state = isChecked ? .on : .off
        layer?.backgroundColor = isHighlighted ? theme.resume.rowSelected.nsColor.cgColor : nil
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }

    @objc private func toggled() {
        onToggle?()
    }

    private static func title(_ row: ResumeRow, theme: Theme) -> NSAttributedString {
        let tokens = theme.resume
        let font = theme.interfaceFont(size: tokens.rowFontSize)
        let color = row.isFinished ? tokens.finishedText : theme.text.primary
        let text = NSMutableAttributedString(
            string: row.title, attributes: [.font: font, .foregroundColor: color.nsColor])
        if let detail = row.detail {
            text.append(
                NSAttributedString(
                    string: " · \(detail)", attributes: [.font: font, .foregroundColor: theme.text.secondary.nsColor]))
        }
        return text
    }
}

/// `.tag`: a pill with the harness or program name.
final class TagView: NSView {
    private let label = NSTextField(labelWithString: "")

    func configure(_ tag: ResumeTag, theme: Theme) {
        let tokens = theme.resume
        wantsLayer = true
        let isAgent = tag.kind == .agent
        layer?.backgroundColor = (isAgent ? tokens.agentTag : tokens.programTag).nsColor.cgColor
        label.stringValue = tag.text
        label.font = theme.interfaceFont(size: tokens.tagFontSize, weight: tokens.tagWeight)
        label.textColor = (isAgent ? tokens.agentTagText : tokens.programTagText).nsColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.tagPaddingHorizontal),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.tagPaddingHorizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: tokens.tagPaddingVertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -tokens.tagPaddingVertical),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}
