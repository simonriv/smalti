/// A plugin's `major.minor.patch`, compared number by number (`0.10.0` > `0.9.1`); missing parts count as 0.
public struct PluginVersion: Comparable, Sendable {
    private let parts: [Int]

    public init(_ text: String) {
        let numbers = text.split(separator: ".").map { Int($0) ?? 0 }
        parts = (numbers + [0, 0, 0]).prefix(max(3, numbers.count)).map { $0 }
    }

    public static func < (lhs: PluginVersion, rhs: PluginVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    public static func == (lhs: PluginVersion, rhs: PluginVersion) -> Bool {
        lhs.parts == rhs.parts
    }
}
