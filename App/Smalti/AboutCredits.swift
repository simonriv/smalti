import AppKit
import SmaltiCore

/// The credits of "Acerca de Smalti" (F7.6): the licenses of what ships inside, and links to the documentation, to
/// support Smalti and to the third-party notices in the bundle.
@MainActor
enum AboutCredits {
    static func text(ghosttyVersion: String, notices: URL?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(
            string: "libghostty \(ghosttyVersion) (MIT) · Sparkle (MIT) · TOMLDecoder (MIT) · Inter (OFL) · "
                + "JetBrains Mono (OFL) · specs de Fig (MIT)\n",
            attributes: [.font: font])
        let links: [(String, URL?)] = [
            ("Documentación", SmaltiLinks.documentation(for: .current)),
            ("Apoyar Smalti", SmaltiLinks.support(for: .current)),
            ("Avisos de terceros", notices),
        ]
        for (index, (title, url)) in links.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: " · ", attributes: [.font: font])) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            attributes[.link] = url
            credits.append(NSAttributedString(string: title, attributes: attributes))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        return credits
    }
}
