import Foundation

/// WCAG 2.x contrast between two colors, taken as opaque (1 for equal colors, 21 for black on white).
public enum ContrastRatio {
    public static func between(_ first: RGBAColor, _ second: RGBAColor) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// The desktop assumed behind the glass when legibility is protected (spec F5): the worst case for the theme.
public enum Backdrop: Sendable {
    /// Behind the dark themes.
    case white
    /// Behind Niebla.
    case black

    public var color: RGBAColor {
        switch self {
        case .white: RGBAColor(red: 255, green: 255, blue: 255, alpha: 1)
        case .black: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
}

extension RGBAColor {
    /// The opaque color seen when `top` (with its alpha) is painted over this color.
    public func underneath(_ top: RGBAColor) -> RGBAColor {
        let alpha = top.alpha
        return RGBAColor(
            red: Self.channel(Double(top.red) * alpha + Double(red) * (1 - alpha)),
            green: Self.channel(Double(top.green) * alpha + Double(green) * (1 - alpha)),
            blue: Self.channel(Double(top.blue) * alpha + Double(blue) * (1 - alpha)),
            alpha: 1)
    }

    /// This color moved `amount` (0–1) of the way toward `target`, opaque.
    public func mixed(toward target: RGBAColor, amount: Double) -> RGBAColor {
        target.withAlpha(amount).paintedOver(self)
    }

    var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    private func paintedOver(_ ground: RGBAColor) -> RGBAColor {
        ground.underneath(self)
    }

    private static func linear(_ channel: UInt8) -> Double {
        let value = Double(channel) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
