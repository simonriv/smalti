import AppKit
import SmaltiCore

/// The glass box of Paleta.dc.html, shared by ⌘K, the help and the feedback overlay (F4.5): shadow outside, blur and
/// tint inside the rounded box, hairline border on top. Sizes come from `PaletteTokens`.
@MainActor
enum OverlayBox {
    /// Puts `stack` inside the box on `host`. Call `updateShadow` from the host's `layout()`.
    static func decorate(_ host: NSView, around stack: NSView, theme: Theme) {
        let palette = theme.palette
        host.wantsLayer = true
        host.layer?.shadowColor = NSColor.black.cgColor
        host.layer?.shadowOpacity = Float(palette.shadowOpacity)
        // CSS blur radius is twice the Core Animation shadow radius; y grows down in CSS and up here.
        host.layer?.shadowRadius = palette.shadowBlur / 2
        host.layer?.shadowOffset = CGSize(width: 0, height: -palette.shadowOffsetY)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = palette.cornerRadius
        blur.layer?.masksToBounds = true
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = palette.cornerRadius
        content.layer?.borderWidth = theme.chrome.hairlineWidth
        content.layer?.borderColor = palette.border.nsColor.cgColor
        content.layer?.backgroundColor = palette.background.nsColor.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        pin(stack, to: content)
        for view in [blur, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
            pin(view, to: host)
        }
    }

    static func updateShadow(of host: NSView, theme: Theme) {
        let radius = theme.palette.cornerRadius
        host.layer?.shadowPath = CGPath(
            roundedRect: host.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The hairline between the field, the list and the footer.
    static func separator(theme: Theme) -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.palette.footerBorder.nsColor.cgColor
        line.heightAnchor.constraint(equalToConstant: theme.chrome.hairlineWidth).isActive = true
        return line
    }

    /// `<kbd>esc</kbd> cerrar`, as the boards write footer hints.
    static func hint(_ keys: String, _ action: String, theme: Theme) -> NSView {
        let row = NSStackView(views: [KbdView(keys, theme: theme), footerLabel(" \(action)", theme: theme)])
        row.spacing = 0
        return row
    }

    static func footerLabel(_ text: String, theme: Theme) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = theme.interfaceFont(size: theme.palette.footerFontSize)
        label.textColor = theme.text.secondary.nsColor
        return label
    }

    static func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
