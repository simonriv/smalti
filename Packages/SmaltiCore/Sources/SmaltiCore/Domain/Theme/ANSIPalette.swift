/// A theme's 16 ANSI colors with the user's edits for that theme (`[appearance.ansi.<tema>]`).
public struct ANSIPalette: Equatable, Sendable {
    public static let range = 0...15
    public let colors: [RGBAColor]

    public init(base: [RGBAColor], overrides: [Int: RGBAColor]) throws(ColorError) {
        if let invalid = overrides.keys.sorted().first(where: { !Self.range.contains($0) }) {
            throw .ansiIndexOutOfRange(invalid)
        }
        colors = base.enumerated().map { overrides[$0.offset] ?? $0.element }
    }
}
