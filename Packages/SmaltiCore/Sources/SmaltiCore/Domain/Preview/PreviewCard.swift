import Foundation

/// What the preview card shows (spec F5.5, `Main.dc.html`): the image's thumbnail, or none when it could not be
/// read, a caption and the word it hangs from.
public struct PreviewCard: Equatable, Sendable {
    public let path: String
    /// What follows the name: "1440×900", "No se pudo leer la imagen" or "Imagen demasiado grande".
    public let detail: String
    public let thumbnail: Data?
    /// The hovered word, in the pane view's points: the card goes under it, or over it when there is no room.
    public let anchor: Rect
    let name: String

    static let nameLimit = 28

    public static func image(_ image: ImageDescription, thumbnail: Data, anchor: Rect) -> PreviewCard {
        PreviewCard(
            path: image.path, detail: image.dimensions, thumbnail: thumbnail, anchor: anchor,
            name: shortName(image.name))
    }

    public static func unreadable(_ image: ImageDescription, anchor: Rect) -> PreviewCard {
        PreviewCard(
            path: image.path, detail: "No se pudo leer la imagen", thumbnail: nil, anchor: anchor,
            name: shortName(image.name))
    }

    public static func tooLarge(path: String, anchor: Rect) -> PreviewCard {
        let name = String(path.split(separator: "/").last ?? "")
        return PreviewCard(
            path: path, detail: "Imagen demasiado grande", thumbnail: nil, anchor: anchor, name: shortName(name))
    }

    /// "landing-v3.png · 1440×900 · ⌘Y para abrir", with the shortcut the keymap binds to Quick Look (final review
    /// m5); without one, or for a card with no image, no hint.
    public func caption(shortcut: String?) -> String {
        guard thumbnail != nil, let shortcut else { return "\(name) · \(detail)" }
        return "\(name) · \(detail) · \(shortcut) para abrir"
    }

    /// The name without control characters, cut in the middle to `nameLimit` so its extension stays visible.
    private static func shortName(_ name: String) -> String {
        let safe = TerminalText.sanitized(name)
        guard safe.count > nameLimit else { return safe }
        let tail = (nameLimit - 1) / 2
        return String(safe.prefix(nameLimit - 1 - tail)) + "…" + String(safe.suffix(tail))
    }
}
