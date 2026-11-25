import AppKit
import SmaltiCore

/// One pane: a rounded, clipped panel that hosts the terminal view. The outer layer is not clipped so the focused
/// pane can glow (`0 0 28px` accent at 13 %) around its accent ring, as `Main.dc.html` draws it.
final class PaneContainerView: NSView {
    let pane: PaneID
    private let clip = NSView()
    /// Glow and 1 px glow ring outside the panel only: a CSS outer box-shadow is never painted under the element,
    /// and the panel is translucent, so the inside of the shadow is masked out.
    private let glow = CAShapeLayer()
    private let glowMask = CAShapeLayer()
    private var theme: Theme
    private var terminalView: NSView?
    private let header: PaneHeaderView
    /// While panes move, the terminal keeps its final size and only the frame animates (spec: no blank frames).
    private var frozenContentSize: NSSize?
    /// F7.5: the oldest command waiting for approval in this pane, over the bottom of the terminal.
    private var approvalCard: ApprovalCardView?

    init(pane: PaneID, theme: Theme) {
        self.pane = pane
        self.theme = theme
        header = PaneHeaderView(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        glowMask.fillRule = .evenOdd
        glow.mask = glowMask
        glow.fillColor = nil
        layer?.addSublayer(glow)
        clip.wantsLayer = true
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = GlassProbe.current != .noPaneMask
        addSubview(clip)
        clip.addSubview(header)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.pane")
        apply(theme, isFocused: false, header: nil)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func embed(_ view: NSView) {
        guard view !== terminalView else { return }
        terminalView?.removeFromSuperview()
        terminalView = view
        // Frame-based: `layout()` sizes it, and `freezeContent` can hold it during an animation.
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = []
        // Review 2: a new terminal view goes under the approval card, never over it.
        clip.addSubview(view, positioned: .below, relativeTo: approvalCard)
        needsLayout = true
    }

    /// A pane whose agent waits gets the amber border, unless it has focus: the focus ring wins.
    func apply(_ theme: Theme, isFocused: Bool, header content: PaneHeaderContent?) {
        self.theme = theme
        content.map { header.show($0, theme: theme) }
        let radius = theme.panel.cornerRadius
        clip.layer?.cornerRadius = radius
        clip.layer?.borderWidth = theme.panel.borderWidth
        let isWaiting = content?.status == .waiting
        let border = isFocused ? theme.focus.ring : (isWaiting ? theme.agent.waitingBorder : theme.panel.border)
        clip.layer?.borderColor = border.nsColor.cgColor
        clip.layer?.backgroundColor = theme.panel.background.nsColor.cgColor
        glow.isHidden = !isFocused
        glow.lineWidth = theme.focus.ringWidth
        glow.strokeColor = theme.focus.glow.nsColor.cgColor
        glow.shadowColor = theme.focus.glow.withAlpha(1).nsColor.cgColor
        glow.shadowOpacity = Float(theme.focus.glow.alpha)
        // CSS blur radius is twice the Core Animation shadow radius.
        glow.shadowRadius = theme.focus.glowRadius / 2
        glow.shadowOffset = .zero
        setAccessibilityValue(isFocused ? "focused" : nil)
    }

    /// F7.5: shows the card while a command waits for approval here, and removes it when none does.
    func showApproval(_ content: ApprovalCardContent?) {
        guard let content else {
            approvalCard?.removeFromSuperview()
            approvalCard = nil
            return
        }
        // Review 2: a card styled with another theme is built again.
        if let shown = approvalCard, shown.theme != theme {
            shown.removeFromSuperview()
            approvalCard = nil
        }
        let card = approvalCard ?? ApprovalCardView(theme: theme)
        if approvalCard == nil {
            approvalCard = card
            clip.addSubview(card, positioned: .above, relativeTo: nil)
        }
        card.show(content)
        needsLayout = true
    }

    private func layoutApprovalCard() {
        guard let card = approvalCard else { return }
        let tokens = theme.approvalCard
        let width = max(0, min(bounds.width - tokens.margin * 2, tokens.maximumWidth))
        let height = max(0, min(card.height(for: width), bounds.height - theme.header.height - tokens.margin * 2))
        card.frame = NSRect(x: (bounds.width - width) / 2, y: tokens.margin, width: width, height: height)
    }

    /// Keeps the terminal at `size` until `unfreezeContent()`, so a frame animation never resizes the surface.
    func freezeContent(at size: NSSize) {
        frozenContentSize = size
        terminalView?.frame = NSRect(x: 0, y: 0, width: size.width, height: max(0, size.height - theme.header.height))
    }

    func unfreezeContent() {
        frozenContentSize = nil
        needsLayout = true
    }

    /// The glow ring is stroked half its width outside the border (`0 0 0 1px`); the mask keeps everything outside
    /// the panel.
    private func layoutGlow() {
        let radius = theme.panel.cornerRadius
        let panel = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // CSS blur reaches about twice its radius.
        let reach = theme.focus.glowRadius * 2
        let ringOffset = theme.focus.ringWidth / 2
        glow.frame = bounds
        glow.path = CGPath(
            roundedRect: bounds.insetBy(dx: -ringOffset, dy: -ringOffset), cornerWidth: radius + ringOffset,
            cornerHeight: radius + ringOffset, transform: nil)
        glow.shadowPath = panel
        let outside = CGMutablePath()
        outside.addRect(bounds.insetBy(dx: -reach, dy: -reach))
        outside.addPath(panel)
        glowMask.frame = bounds
        glowMask.path = outside
    }

    override func layout() {
        super.layout()
        clip.frame = bounds
        let headerHeight = min(theme.header.height, bounds.height)
        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
        layoutGlow()
        layoutApprovalCard()
        guard frozenContentSize == nil else { return }
        terminalView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerHeight)
    }
}
