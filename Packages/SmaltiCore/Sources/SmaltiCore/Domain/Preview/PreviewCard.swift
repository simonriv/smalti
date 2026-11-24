import Foundation

/// What the preview card shows (spec F5.5, `Main.dc.html`): the image's thumbnail, or none when it could not be
/// read, a caption and the word it hangs from.
public struct PreviewCard: Equatable, Sendable {
    public let path: String
    public let caption: String
    public let thumbnail: Data?
    /// The hovered word, in the pane view's points: the card goes under it, or over it when there is no room.
    public let anchor: Rect

    static let nameLimit = 28

    /// "landing-v3.png · 1440×900 · ⌘Y para abrir".
    public static func image(_ image: ImageDescription, thumbnail: Data, anchor: Rect) -> PreviewCard {
        PreviewCard(
            path: image.path, caption: "\(shortName(image.name)) · \(image.dimensions) · ⌘Y para abrir",
            thumbnail: thumbnail, anchor: anchor)
    }

    public static func unreadable(_ image: ImageDescription, anchor: Rect) -> PreviewCard {
        PreviewCard(
            path: image.path, caption: "\(shortName(image.name)) · No se pudo leer la imagen", thumbnail: nil,
            anchor: anchor)
    }

    public static func tooLarge(path: String, anchor: Rect) -> PreviewCard {
        let name = String(path.split(separator: "/").last ?? "")
        return PreviewCard(
            path: path, caption: "\(shortName(name)) · Imagen demasiado grande", thumbnail: nil, anchor: anchor)
    }

    /// The name without control characters, cut in the middle to `nameLimit` so its extension stays visible.
    private static func shortName(_ name: String) -> String {
        let safe = TerminalText.sanitized(name)
        guard safe.count > nameLimit else { return safe }
        let tail = (nameLimit - 1) / 2
        return String(safe.prefix(nameLimit - 1 - tail)) + "…" + String(safe.suffix(tail))
    }
}
