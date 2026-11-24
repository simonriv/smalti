/// The terminal's font size: the configured `font_size` plus the steps the user took with ⌘+ and ⌘−, kept between
/// 6 and 72 points. It lasts while the app runs; the permanent size lives in the TOML.
public struct FontScale: Equatable, Sendable {
    public static let range = 6.0...72.0
    static let step = 1.0

    private let base: Double
    private let offset: Double

    public init(base: Double) {
        self.init(base: base, offset: 0)
    }

    private init(base: Double, offset: Double) {
        self.base = base
        self.offset = offset
    }

    public var size: Double { min(max(base + offset, Self.range.lowerBound), Self.range.upperBound) }

    public func increased() -> FontScale { stepped(by: Self.step) }

    public func decreased() -> FontScale { stepped(by: -Self.step) }

    public func reset() -> FontScale { FontScale(base: base) }

    /// A reloaded `font_size` keeps the steps the user took.
    public func rebased(_ newBase: Double) -> FontScale { FontScale(base: newBase, offset: offset) }

    /// Steps from the size actually shown, so one ⌘− after hitting 72 gives 71.
    private func stepped(by amount: Double) -> FontScale {
        let target = min(max(size + amount, Self.range.lowerBound), Self.range.upperBound)
        return FontScale(base: base, offset: target - base)
    }
}
