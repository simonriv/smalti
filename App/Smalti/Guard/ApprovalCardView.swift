import AppKit
import SmaltiCore

/// What the card of a pane shows: its oldest waiting command and how many wait.
struct ApprovalCardContent: Equatable {
    let approval: PendingApproval
    let position: Int
    let count: Int
    let workspace: String
    let approveKeys: String
    let rejectKeys: String
    let now: Date

    /// «vence en 10 min», never below 1.
    var expiresText: String {
        let minutes = max(1, Int((approval.deadline.timeIntervalSince(now) / 60).rounded(.up)))
        return "vence en \(minutes) min"
    }
}

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
    private let footer = NSTextField(labelWithString: "")
    private let tokens: ApprovalCardTokens
    private let theme: Theme
    private(set) var content: ApprovalCardContent?

    init(theme: Theme) {
        self.theme = theme
        tokens = theme.approvalCard
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
        footer.font = theme.interfaceFont(size: tokens.footerFontSize, weight: 500)
        footer.textColor = tokens.body.nsColor
        subject.setAccessibilityIdentifier("smalti.approvalEnvironment")
        [title, subject, footer].forEach { $0.lineBreakMode = .byTruncatingTail }
    }

    private func styleCommand() {
        command.isEditable = false
        command.isSelectable = true
        command.drawsBackground = false
        command.font = theme.monospacedFont(size: tokens.commandFontSize)
        command.textColor = tokens.title.nsColor
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
        guard content != self.content else { return }
        self.content = content
        let subjectOfCard = content.approval.subject
        title.stringValue = "Espera tu aprobación · \(content.workspace)"
        counter.stringValue = "\(content.position) de \(content.count)"
        subject.attributedStringValue = subjectText(subjectOfCard)
        subject.setAccessibilityValue(subjectOfCard.environment.label)
        command.string = subjectOfCard.command
        command.setAccessibilityValue(subjectOfCard.command)
        footer.stringValue = "\(content.approveKeys) aprobar   \(content.rejectKeys) rechazar   \(content.expiresText)"
        setAccessibilityValue("\(content.position) de \(content.count)")
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
        bold[.foregroundColor] = tokens.title.nsColor
        let text = NSMutableAttributedString(
            string: "\(subject.headline?.rule ?? "comando") contra ", attributes: regular)
        text.append(NSAttributedString(string: subject.environment.label, attributes: bold))
        let detail = [subject.environment.host, subject.environment.detail].compactMap { $0 }.joined(separator: " · ")
        if !detail.isEmpty { text.append(NSAttributedString(string: " · \(detail)", attributes: regular)) }
        return text
    }

    /// The card's height for `width`: the command up to `maximumCommandLines` lines, then it scrolls.
    func height(for width: CGFloat) -> CGFloat {
        let inner = width - tokens.padding * 2
        let line = (command.font?.boundingRectForFont.height ?? tokens.commandFontSize * 1.3).rounded(.up)
        command.frame.size.width = inner
        command.layoutManager?.ensureLayout(for: command.textContainer ?? NSTextContainer())
        let used = command.layoutManager?.usedRect(for: command.textContainer ?? NSTextContainer()).height ?? line
        let commandHeight = min(used, line * CGFloat(tokens.maximumCommandLines)) + tokens.commandPadding
        let rows = [title, subject, footer].map { $0.intrinsicContentSize.height }.reduce(0, +)
        return (tokens.padding * 2 + rows + commandHeight + tokens.gap * 3).rounded(.up)
    }

    override func layout() {
        super.layout()
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
        let footerHeight = footer.intrinsicContentSize.height
        footer.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: footerHeight)
        let commandBottom = inner.minY + footerHeight + tokens.gap
        commandScroll.frame = NSRect(
            x: inner.minX, y: commandBottom, width: inner.width, height: max(0, top - tokens.gap - commandBottom))
        command.frame.size.width = commandScroll.contentSize.width
    }
}
