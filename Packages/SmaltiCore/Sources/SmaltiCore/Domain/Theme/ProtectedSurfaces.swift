/// A surface that carries text (spec F5: panels, strip, headers, status bar, overlays): its own color and the colors
/// painted on it that must stay at 4.5:1.
public struct ProtectedSurface: Equatable, Sendable {
    /// The surface color; its alpha is what protection may raise.
    public let tint: RGBAColor
    public let colors: [RGBAColor]

    public init(tint: RGBAColor, colors: [RGBAColor]) {
        self.tint = tint
        self.colors = colors
    }
}
