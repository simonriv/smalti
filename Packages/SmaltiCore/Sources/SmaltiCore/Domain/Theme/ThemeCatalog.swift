/// The four themes and how the user's appearance settings turn one of them into what is painted (spec F5).
public enum ThemeCatalog {
    public static func theme(_ id: ThemeID) -> Theme {
        switch id {
        case .obsidiana: Theme.obsidian
        case .niebla: niebla
        case .ambarNocturno: ambarNocturno
        case .bosque: bosque
        }
    }

    private static let niebla = Theme.make(name: ThemeID.niebla.displayName, colors: .niebla)
    private static let ambarNocturno = Theme.make(name: ThemeID.ambarNocturno.displayName, colors: .ambarNocturno)
    private static let bosque = Theme.make(name: ThemeID.bosque.displayName, colors: .bosque)

    /// The colors the 4.5:1 rule covers on a panel: text, secondary and the ANSI colors but the background pair.
    public static func protectedColors(of theme: Theme, id: ThemeID) -> [RGBAColor] {
        [theme.text.primary, theme.text.secondary] + chromaticANSI(of: theme, id: id)
    }

    /// The theme of `appearance.theme` with the user's sizes, glass, accent and ANSI edits, protected when asked.
    public static func apply(_ appearance: AppearanceSettings) -> AppliedTheme {
        let id = appearance.theme
        var theme = theme(id).applying(appearance)
        let overrides = appearance.ansiOverrides[id] ?? .none
        theme.terminal.palette = ANSIPalette(base: theme.terminal.palette, overrides: overrides).colors
        theme.resume.primaryButtonText = textOnAccent(theme)
        guard appearance.protectLegibility else {
            let opacities = SurfaceOpacities(
                panel: theme.panel.background.alpha, chrome: 0, overlay: theme.palette.background.alpha)
            return AppliedTheme(theme: theme, opacities: opacities, adjustedColorCount: 0)
        }
        return Protection(theme: theme, id: id).applied()
    }

    /// The design's text on accent-filled buttons, or the theme's text color when a TOML accent makes it unreadable
    /// (block 1 review, M5): whichever contrasts more with the effective accent.
    private static func textOnAccent(_ theme: Theme) -> RGBAColor {
        let design = theme.resume.primaryButtonText
        let text = theme.text.primary
        let isDesignBetter = ContrastRatio.between(design, theme.accent) >= ContrastRatio.between(text, theme.accent)
        return isDesignBetter ? design : text
    }

    fileprivate static func chromaticANSI(of theme: Theme, id: ThemeID) -> [RGBAColor] {
        theme.terminal.palette.enumerated().filter { !id.backgroundIndices.contains($0.offset) }.map(\.element)
    }
}

/// What the app paints: the final theme, the opacity of each protected surface and how many colors protection moved.
public struct AppliedTheme: Equatable, Sendable {
    public let theme: Theme
    public let opacities: SurfaceOpacities
    /// "Ajustados por legibilidad: N colores": ANSI colors that could not reach 4.5:1 by opacity alone.
    public let adjustedColorCount: Int
}

/// Opacities of the surfaces that carry text. `panel` and `overlay` are their background alphas; `chrome` is an extra
/// glass-colored layer behind the strip and the status bar (0 when not needed).
public struct SurfaceOpacities: Equatable, Sendable {
    public let panel: Double
    public let chrome: Double
    public let overlay: Double
}

/// "Proteger legibilidad" over the theme's worst desktop.
private struct Protection {
    var theme: Theme
    let id: ThemeID

    private var glassGround: RGBAColor { id.worstBackdrop.color.underneath(theme.window.background) }

    func applied() -> AppliedTheme {
        var protected = self
        let panel = protected.raisePanel()
        let adjusted = protected.adjustPanelColors()
        let overlay = protected.raiseOverlay()
        protected.theme.legibleGround = protected.glassGround.underneath(protected.theme.panel.background)
        let opacities = SurfaceOpacities(panel: panel, chrome: chromeOpacity(), overlay: overlay)
        return AppliedTheme(theme: protected.theme, opacities: opacities, adjustedColorCount: adjusted)
    }

    /// Colors that cannot pass even on an opaque panel are adjusted afterwards, so they never force opacity 1.
    private mutating func raisePanel() -> Double {
        let tint = theme.panel.background
        let opaquePanel = glassGround.underneath(tint.withAlpha(1))
        let reachable = ThemeCatalog.protectedColors(of: theme, id: id).filter {
            ContrastRatio.between($0, opaquePanel) >= LegibilityGuard.searchContrast
        }
        let needed = LegibilityGuard.minimumOpacity(
            for: ProtectedSurface(tint: tint, colors: reachable), over: glassGround)
        let alpha = max(tint.alpha, needed)
        theme.panel.background = tint.withAlpha(alpha)
        // The observatory's cards are the panel's tint and carry the same text.
        theme.observatory.cardBackground = theme.panel.background
        return alpha
    }

    private mutating func adjustPanelColors() -> Int {
        let ground = glassGround.underneath(theme.panel.background)
        let anchor = theme.text.primary
        theme.text.ghostText = LegibilityGuard.legible(theme.text.ghostText, on: ground, toward: anchor)
        var moved = 0
        theme.terminal.palette = theme.terminal.palette.enumerated().map { index, color in
            guard !id.backgroundIndices.contains(index) else { return color }
            let legible = LegibilityGuard.legible(color, on: ground, toward: anchor)
            if legible != color { moved += 1 }
            return legible
        }
        return moved
    }

    private mutating func raiseOverlay() -> Double {
        let tint = theme.palette.background
        let colors = [theme.text.primary, theme.text.title, theme.text.secondary]
        let needed = LegibilityGuard.minimumOpacity(
            for: ProtectedSurface(tint: tint, colors: colors), over: glassGround)
        let alpha = max(tint.alpha, needed)
        theme.palette.background = tint.withAlpha(alpha)
        return alpha
    }

    private func chromeOpacity() -> Double {
        let colors = [theme.text.primary, theme.text.title, theme.text.secondary]
        return LegibilityGuard.minimumOpacity(
            for: ProtectedSurface(tint: theme.window.background.withAlpha(1), colors: colors), over: glassGround)
    }
}
