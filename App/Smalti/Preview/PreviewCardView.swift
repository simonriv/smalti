import AppKit
import SmaltiCore

/// The image preview card of `Main.dc.html` (spec F5.5): the thumbnail over its caption, in the completion menu's
/// surface. It never takes the mouse, so the terminal under it keeps tracking the pointer.
@MainActor
final class PreviewCardView: NSView {
    private let imageView = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let tokens: PreviewCardTokens

    init(theme: Theme) {
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

    /// The card's size for its content: the board's width; the image box only when there is a thumbnail.
    var cardSize: NSSize {
        let imageHeight = imageView.image == nil ? 0 : tokens.imageSize.height + tokens.gap
        let height = tokens.padding * 2 + imageHeight + caption.intrinsicContentSize.height
        return NSSize(width: tokens.width, height: height)
    }

    func show(_ card: PreviewCard) {
        imageView.image = card.thumbnail.flatMap(NSImage.init(data:))
        caption.stringValue = card.caption
        setAccessibilityLabel(card.caption)
        needsLayout = true
    }

    /// Fades in (`overlayAppearDuration`), or appears at once with "Reducir movimiento".
    func appear(isMotionReduced: Bool) {
        setAccessibilityValue(isMotionReduced ? "sin fundido" : "con fundido")
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

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: tokens.padding, dy: tokens.padding)
        let captionHeight = caption.intrinsicContentSize.height
        caption.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: captionHeight)
        imageView.frame = NSRect(
            x: inner.minX, y: inner.maxY - tokens.imageSize.height, width: inner.width,
            height: tokens.imageSize.height)
        imageView.isHidden = imageView.image == nil
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: tokens.cornerRadius, cornerHeight: tokens.cornerRadius, transform: nil)
    }
}
