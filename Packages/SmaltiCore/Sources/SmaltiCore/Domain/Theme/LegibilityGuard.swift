/// "Proteger legibilidad" (spec F5): how opaque a surface must be, and how far a color must move, for text to keep
/// 4.5:1 over the worst desktop.
public enum LegibilityGuard {
    public static let minimumContrast = 4.5
    /// What the searches aim for: Core Animation blends layers without rounding each one to 8 bits, so a step that
    /// reaches exactly 4.5 here can land at 4.48 on screen (block 1 review, I1).
    static let searchContrast = minimumContrast + 0.05
    private static let steps = 100

    /// The smallest opacity, in steps of 0.01, at which every color of `surface` reaches `minimumContrast` over the
    /// opaque `ground` beneath it; 1 when some color never does.
    public static func minimumOpacity(for surface: ProtectedSurface, over ground: RGBAColor) -> Double {
        let step = (0...steps).first { step in
            let painted = ground.underneath(surface.tint.withAlpha(Double(step) / Double(steps)))
            return surface.colors.allSatisfy { isLegible($0, on: painted) }
        }
        return Double(step ?? steps) / Double(steps)
    }

    /// `color` moved toward `anchor` in steps of 1 % until it reaches `minimumContrast` on `ground`; unchanged when it
    /// already does, `anchor` when no step does.
    public static func legible(_ color: RGBAColor, on ground: RGBAColor, toward anchor: RGBAColor) -> RGBAColor {
        let candidates = (0...steps).lazy.map { color.mixed(toward: anchor, amount: Double($0) / Double(steps)) }
        return candidates.first { isLegible($0, on: ground) } ?? anchor
    }

    /// Every color made legible, and how many had to move.
    public static func legible(_ colors: [RGBAColor], on ground: RGBAColor, toward anchor: RGBAColor) -> LegibleColors {
        let adjusted = colors.map { legible($0, on: ground, toward: anchor) }
        let moved = zip(colors, adjusted).count { $0 != $1 }
        return LegibleColors(colors: adjusted, adjustedCount: moved)
    }

    private static func isLegible(_ color: RGBAColor, on ground: RGBAColor) -> Bool {
        ContrastRatio.between(color, ground) >= searchContrast
    }
}

/// Colors after protection, and how many of them it changed ("Ajustados por legibilidad: N colores").
public struct LegibleColors: Equatable, Sendable {
    public let colors: [RGBAColor]
    public let adjustedCount: Int
}
