import AppKit
import SmaltiCore

/// The approval card of F7.5 (no board draws it; see `ApprovalCardTokens`): the waiting command at the bottom of its
/// pane, with the workspace, the rule, the environment and the keys that decide it.
@MainActor
final class ApprovalCardView: NSView {
    private let dot = NSView()
    private let title = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let subject = NSTextField(labelWithString: "")
    private let commandScroll = NSScrollView()
    private let command = NSTextView()
    /// «⇧⌘↩ aprobar   ⇧⌘⎋ rechazar   vence en 10 min», the keys as the palette draws them.
    private let footer = NSStackView()
    private let approveKey: KbdView
    private let rejectKey: KbdView
    private let approveLabel = NSTextField(labelWithString: "aprobar")
    private let rejectLabel = NSTextField(labelWithString: "rechazar")
    private let expires = NSTextField(labelWithString: "")
    private let tokens: ApprovalCardTokens
    /// The theme it was styled with: a card shown after a theme change is built again.
    let theme: Theme
    private(set) var content: ApprovalCardContent?

    init(theme: Theme) {
        self.theme = theme
        tokens = theme.approvalCard
        approveKey = KbdView("", theme: theme)
        rejectKey = KbdView("", theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = tokens.cornerRadius
        layer?.borderWidth = theme.chrome.hairlineWidth
        layer?.borderColor = tokens.border.nsColor.cgColor
        layer?.backgroundColor = tokens.background.nsColor.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(tokens.shadowOpacity)
        // CSS blur radius is twice the Core Animation radius; y grows down in CSS and up here.
        layer?.shadowRadius = tokens.shadowRadius / 2
        layer?.shadowOffset = CGSize(width: 0, height: -tokens.shadowOffsetY)
        styleLabels()
        styleCommand()
        [dot, title, counter, subject, commandScroll, footer].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.approvalCard")
        setAccessibilityTitle(theme.name)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func styleLabels() {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = tokens.dotSize / 2
        dot.layer?.backgroundColor = tokens.dot.nsColor.cgColor
        title.font = theme.interfaceFont(size: tokens.titleFontSize, weight: 600)
        title.textColor = tokens.title.nsColor
        counter.font = theme.interfaceFont(size: tokens.footerFontSize, weight: 500)
        counter.textColor = tokens.body.nsColor
        counter.alignment = .right
        for label in [approveLabel, rejectLabel, expires] {
            label.font = theme.interfaceFont(size: tokens.footerFontSize, weight: 500)
            label.textColor = tokens.body.nsColor
        }
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = tokens.gap / 2
        footer.addArrangedSubview(approveKey)
        footer.addArrangedSubview(approveLabel)
        footer.setCustomSpacing(tokens.gap * 2, after: approveLabel)
        footer.addArrangedSubview(rejectKey)
        footer.addArrangedSubview(rejectLabel)
        footer.setCustomSpacing(tokens.gap * 2, after: rejectLabel)
        footer.addArrangedSubview(expires)
        footer.setAccessibilityIdentifier("smalti.approvalFooter")
        subject.setAccessibilityIdentifier("smalti.approvalEnvironment")
        [title, subject].forEach { $0.lineBreakMode = .byTruncatingTail }
    }

    private func styleCommand() {
        command.isEditable = false
        command.isSelectable = true
        command.drawsBackground = false
        command.font = theme.monospacedFont(size: tokens.commandFontSize)
        command.textColor = tokens.emphasis.nsColor
        command.textContainerInset = NSSize(width: tokens.commandPadding, height: tokens.commandPadding / 2)
        command.isVerticallyResizable = true
        command.textContainer?.widthTracksTextView = true
        command.setAccessibilityIdentifier("smalti.approvalCommand")
        commandScroll.documentView = command
        commandScroll.hasVerticalScroller = true
        commandScroll.drawsBackground = false
        commandScroll.wantsLayer = true
        commandScroll.layer?.cornerRadius = tokens.commandCornerRadius
        commandScroll.layer?.backgroundColor = tokens.commandBackground.nsColor.cgColor
    }

    func show(_ content: ApprovalCardContent) {
        let isSameCommand = self.content.map(content.showsSameCommand(as:)) ?? false
        self.content = content
        counter.stringValue = content.counter
        approveKey.text = content.approveKeys
        rejectKey.text = content.rejectKeys
        expires.stringValue = content.expiresText
        footer.setAccessibilityLabel(content.footer)
        setAccessibilityValue(content.counter)
        // The counter's width changes ("1 de 2"): every refresh lays the card out again.
        needsLayout = true
        // Review 2: the same command keeps its text view, so its scroll and selection survive every refresh.
        guard !isSameCommand else { return }
        let subjectOfCard = content.approval.subject
        title.stringValue = "Espera tu aprobación · \(content.workspace)"
        subject.attributedStringValue = subjectText(subjectOfCard)
        command.string = subjectOfCard.command
        command.setAccessibilityValue(subjectOfCard.command)
        setAccessibilityLabel("\(subjectOfCard.summary): \(subjectOfCard.command)")
        needsLayout = true
    }

    /// «supabase db push contra **PROD** · proyecto enlazado»: the environment in bold, no new color.
    private func subjectText(_ subject: ApprovalSubject) -> NSAttributedString {
        let regular: [NSAttributedString.Key: Any] = [
            .font: theme.interfaceFont(size: tokens.bodyFontSize, weight: 500), .foregroundColor: tokens.body.nsColor,
        ]
        var bold = regular
        bold[.font] = theme.interfaceFont(size: tokens.bodyFontSize, weight: 700)
        bold[.foregroundColor] = tokens.emphasis.nsColor
        let text = NSMutableAttributedString(
            string: "\(subject.headline?.rule ?? "comando") contra ", attributes: regular)
        text.append(NSAttributedString(string: subject.environment.label, attributes: bold))
        let detail = [subject.environment.host, subject.environment.detail].compactMap { $0 }.joined(separator: " · ")
        if !detail.isEmpty { text.append(NSAttributedString(string: " · \(detail)", attributes: regular)) }
        return text
    }

    /// The card's height for `width`: the command up to `maximumCommandLines` lines, then it scrolls. The text is
    /// measured at the scroll view's content width (review 2: legacy scrollers take room).
    func height(for width: CGFloat) -> CGFloat {
        let inner = max(0, width - tokens.padding * 2)
        let scroller =
            commandScroll.hasVerticalScroller && NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        let line = (command.font?.boundingRectForFont.height ?? tokens.commandFontSize * 1.3).rounded(.up)
        command.frame.size.width = max(0, inner - scroller)
        command.layoutManager?.ensureLayout(for: command.textContainer ?? NSTextContainer())
        let used = command.layoutManager?.usedRect(for: command.textContainer ?? NSTextContainer()).height ?? line
        let commandHeight = min(used, line * CGFloat(tokens.maximumCommandLines)) + tokens.commandPadding
        return (fixedRowsHeight + commandHeight + tokens.gap).rounded(.up)
    }

    /// Padding, title, subject and footer with their gaps: what shows even when the command has no room.
    private var fixedRowsHeight: CGFloat {
        let rows = title.intrinsicContentSize.height + subject.intrinsicContentSize.height + footer.fittingSize.height
        return tokens.padding * 2 + rows + tokens.gap * 2
    }

    override func layout() {
        super.layout()
        // Review 2: in a pane too low for the command, only title and footer show, never overlapping.
        let hasRoom = bounds.height >= fixedRowsHeight + tokens.gap
        subject.isHidden = !hasRoom
        commandScroll.isHidden = !hasRoom
        let inner = bounds.insetBy(dx: tokens.padding, dy: tokens.padding)
        var top = inner.maxY
        let titleHeight = title.intrinsicContentSize.height
        top -= titleHeight
        dot.frame = NSRect(
            x: inner.minX, y: top + (titleHeight - tokens.dotSize) / 2, width: tokens.dotSize, height: tokens.dotSize)
        let titleX = inner.minX + tokens.dotSize + tokens.gap
        let counterWidth = counter.intrinsicContentSize.width
        counter.frame = NSRect(x: inner.maxX - counterWidth, y: top, width: counterWidth, height: titleHeight)
        title.frame = NSRect(
            x: titleX, y: top, width: inner.maxX - counterWidth - tokens.gap - titleX, height: titleHeight)
        top -= tokens.gap + subject.intrinsicContentSize.height
        subject.frame = NSRect(x: inner.minX, y: top, width: inner.width, height: subject.intrinsicContentSize.height)
        let footerHeight = footer.fittingSize.height
        footer.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: footerHeight)
        let commandBottom = inner.minY + footerHeight + tokens.gap
        commandScroll.frame = NSRect(
            x: inner.minX, y: commandBottom, width: inner.width, height: max(0, top - tokens.gap - commandBottom))
        command.frame.size.width = commandScroll.contentSize.width
    }
}
