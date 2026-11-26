import AppKit
import SmaltiCore

/// The pieces above the list: the session line, the unidentified banner, the search field and its scope line.
@MainActor
enum TimelineParts {
    static func session(_ info: TimelineScreen.SessionInfo, theme: Theme) -> [NSView] {
        let tokens = theme.timeline
        let line = ObservatoryText.label(
            info.line, .init(size: tokens.sessionLineSize, color: theme.text.primary), theme: theme)
        let first = NSStackView(views: [StatusDot(diameter: theme.header.dotSize, style: info.dot), line])
        first.spacing = 8
        let title = ObservatoryText.label(
            info.title, .init(size: tokens.sessionTitleSize, color: theme.text.title, weight: 500), theme: theme)
        title.setAccessibilityIdentifier("smalti.timeline.session.title")
        let figures = ObservatoryText.number(info.figures, .init(size: 10.5, color: theme.text.secondary), theme: theme)
        figures.setAccessibilityIdentifier("smalti.timeline.session.figures")
        return [first, title, figures]
    }

    static func banner(_ text: String, theme: Theme) -> NSView {
        let tokens = theme.timeline
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = theme.interfaceFont(size: 11.5)
        label.textColor = theme.text.primary.nsColor
        label.setAccessibilityIdentifier("smalti.timeline.banner")
        let dot = StatusDot(diameter: theme.header.dotSize, color: tokens.unidentifiedDot)
        let stack = NSStackView(views: [dot, label])
        stack.alignment = .top
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = tokens.bannerBackground.nsColor.cgColor
        label.preferredMaxLayoutWidth = tokens.width - 2 * tokens.padding - 40
        return stack
    }

    static func searchBox(_ field: NSTextField, theme: Theme) -> NSView {
        let tokens = theme.processes
        let glyph = NSImageView(
            image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = theme.text.secondary.nsColor
        let stack = NSStackView(views: [glyph, field])
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: tokens.filterPadding, bottom: 0, right: tokens.filterPadding)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = tokens.filterRadius
        stack.layer?.borderWidth = theme.chrome.hairlineWidth
        stack.layer?.borderColor = theme.focus.ring.nsColor.cgColor
        stack.layer?.backgroundColor = tokens.filterBackground.nsColor.cgColor
        stack.heightAnchor.constraint(equalToConstant: theme.timeline.searchFieldHeight).isActive = true
        stack.widthAnchor.constraint(equalToConstant: theme.timeline.width - 2 * theme.timeline.padding).isActive = true
        return stack
    }

    static func scope(_ scope: String, root: String, summary: String, theme: Theme) -> NSView {
        let name = ObservatoryText.label(scope, .init(size: 11, color: theme.text.primary), theme: theme)
        let path = ObservatoryText.number(root, .init(size: 10.5, color: theme.text.secondary), theme: theme)
        path.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let figures = ObservatoryText.label(summary, .init(size: 11, color: theme.text.secondary), theme: theme)
        figures.setAccessibilityIdentifier("smalti.timeline.search.summary")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [name, path, spacer, figures])
        stack.spacing = 8
        stack.widthAnchor.constraint(equalToConstant: theme.timeline.width - 2 * theme.timeline.padding).isActive = true
        return stack
    }
}
