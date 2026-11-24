/// `[preview]` in `config.toml` (spec F5.5): whether hovering an image name shows its thumbnail.
public struct PreviewSettings: Equatable, Sendable {
    public var hover: Bool

    public init(hover: Bool) {
        self.hover = hover
    }

    public static let standard = PreviewSettings(hover: true)
}
