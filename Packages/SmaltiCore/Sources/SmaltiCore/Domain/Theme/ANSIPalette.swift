/// A theme's 16 ANSI colors with the user's edits for that theme (`[appearance.ansi.<tema>]`).
public struct ANSIPalette: Equatable, Sendable {
    public let colors: [RGBAColor]

    public init(base: [RGBAColor], overrides: ANSIOverrides) {
        colors = base.enumerated().map { overrides.colors[$0.offset] ?? $0.element }
    }
}

/// The user's ANSI edits for one theme, by index. Built only with indices 0–15, so applying them cannot fail.
public struct ANSIOverrides: Equatable, Sendable {
    public static let range = 0...15
    public static let none = ANSIOverrides(validated: [:])
    public let colors: [Int: RGBAColor]

    public init(_ colors: [Int: RGBAColor]) throws(ColorError) {
        if let invalid = colors.keys.sorted().first(where: { !Self.range.contains($0) }) {
            throw .ansiIndexOutOfRange(invalid)
        }
        self.init(validated: colors)
    }

    private init(validated colors: [Int: RGBAColor]) {
        self.colors = colors
    }
}
