/// sRGB color with 8-bit channels and a 0–1 alpha, as written in docs/design.
public struct RGBAColor: Equatable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#rrggbb`, lowercase, without alpha: how zsh and config files write a color.
    public var hexString: String {
        "#"
            + [red, green, blue].map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    /// Parses `#rrggbb` with full opacity.
    public init(hex: String) throws(ColorError) {
        let digits = hex.dropFirst()
        guard hex.hasPrefix("#"), digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw .invalidHex(hex)
        }
        self.init(
            red: UInt8(truncatingIfNeeded: value >> 16),
            green: UInt8(truncatingIfNeeded: value >> 8),
            blue: UInt8(truncatingIfNeeded: value),
            alpha: 1)
    }

    /// The same color with another opacity.
    public func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public enum ColorError: Error, Equatable, Sendable {
    case invalidHex(String)
    /// `[appearance.ansi.<tema>]` names an index outside 0–15.
    case ansiIndexOutOfRange(Int)
}
