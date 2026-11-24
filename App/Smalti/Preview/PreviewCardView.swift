import AppKit
import SmaltiCore

/// The image preview card of `Main.dc.html` (spec F5.5): the thumbnail over its caption, in the completion menu's
/// surface. It never takes the mouse, so the terminal under it keeps tracking the pointer.
@MainActor
final class PreviewCardView: NSView {
    private let imageView = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let tokens: PreviewCardTokens
    /// The theme it was styled with: a card shown after a theme change is built again.
    let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        tokens = theme.previewCard
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
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = tokens.imageCornerRadius
        imageView.layer?.masksToBounds = true
        caption.font = theme.interfaceFont(size: tokens.captionFontSize, weight: 500)
        caption.textColor = tokens.caption.nsColor
        caption.lineBreakMode = .byTruncatingMiddle
        caption.maximumNumberOfLines = 1
        [imageView, caption].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("preview.card")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The card's size for its content: the board's width, wider when the caption needs it (on the board the caption
    /// overflows the card; here the name, the size and "⌘Y para abrir" always show whole); the image box only when there
    /// is a thumbnail.
    var cardSize: NSSize {
        let imageHeight = imageView.image == nil ? 0 : tokens.imageSize.height + tokens.gap
        let height = tokens.padding * 2 + imageHeight + caption.intrinsicContentSize.height
        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude, height: caption.intrinsicContentSize.height)
        let captionWidth = caption.sizeThatFits(unbounded).width
        let width = max(tokens.width, (captionWidth + tokens.padding * 2).rounded(.up))
        return NSSize(width: width, height: height)
    }

    func show(_ card: PreviewCard) {
        imageView.image = card.thumbnail.flatMap(NSImage.init(data:))
        caption.stringValue = card.caption
        setAccessibilityLabel(card.caption)
        needsLayout = true
    }

    /// Fades in (`overlayAppearDuration`), or appears at once with "Reducir movimiento".
    func appear(isMotionReduced: Bool) {
        // Only for UI tests that stand in for "Reducir movimiento"; VoiceOver never hears it otherwise.
        if UserDefaults.standard.object(forKey: Motion.reduceMotionKey) != nil {
            setAccessibilityValue(isMotionReduced ? "sin fundido" : "con fundido")
        }
        guard !isMotionReduced else {
            alphaValue = 1
            return
        }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = tokens.appearDuration
            animator().alphaValue = 1
        }
    }

    /// The thumbnail fitted in the board's 194 × 104 box, centered, so its own corners are the ones rounded.
    private func fittedImageFrame(in inner: NSRect) -> NSRect {
        let box = NSSize(width: min(tokens.imageSize.width, inner.width), height: tokens.imageSize.height)
        let image = imageView.image?.size ?? box
        let scale = min(box.width / max(image.width, 1), box.height / max(image.height, 1), 1)
        let size = NSSize(width: image.width * scale, height: image.height * scale)
        let top = inner.maxY - tokens.imageSize.height
        return NSRect(
            x: inner.midX - size.width / 2, y: top + (tokens.imageSize.height - size.height) / 2, width: size.width,
            height: size.height)
    }

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: tokens.padding, dy: tokens.padding)
        let captionHeight = caption.intrinsicContentSize.height
        caption.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: captionHeight)
        imageView.frame = fittedImageFrame(in: inner)
        imageView.isHidden = imageView.image == nil
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: tokens.cornerRadius, cornerHeight: tokens.cornerRadius, transform: nil)
    }
}
