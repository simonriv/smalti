extension Theme {
    /// The theme's color for a segment's role, after protection (the applied theme's palette and text).
    /// With "Proteger legibilidad" the role's color also reaches 4.5:1 on the protected panel and on its own pill
    /// (final review, I4: Niebla's waiting amber was 2.8:1), moving toward the text color as protection does.
    func color(for role: SegmentColor) -> RGBAColor {
        guard let ground = legibleGround else { return baseColor(for: role) }
        var color = protectedColor(for: role)
        for _ in 0..<Self.pillPasses {
            let pill = PillsStyle.background(of: color, over: panel.background)
            color = LegibilityGuard.legible(color, on: pill, toward: text.primary)
        }
        return color
    }

    /// The role's color at 4.5:1 over the protected panel when "Proteger legibilidad" is on; as is otherwise.
    func protectedColor(for role: SegmentColor) -> RGBAColor {
        let base = baseColor(for: role)
        guard let ground = legibleGround else { return base }
        return LegibilityGuard.legible(base, on: ground, toward: text.primary)
    }

    /// The pill's tint follows the color it holds: a second pass settles it.
    private static let pillPasses = 2

    private func baseColor(for role: SegmentColor) -> RGBAColor {
        switch role {
        case .accent: accent
        case .ansi(let index): terminal.palette.indices.contains(index) ? terminal.palette[index] : text.primary
        case .secondary: text.secondary
        case .waiting: agent.waiting
        case .failed: agent.failed
        }
    }
}

/// Icons the chosen set cannot draw ("Sin iconos") go away together with the space after them.
func drawableRuns(_ line: [StyledRun], icons: PromptIcons) -> [StyledRun] {
    func isUndrawable(_ run: StyledRun) -> Bool {
        if case .icon(let icon) = run.content { return icons.character(for: icon) == nil }
        return false
    }
    return line.indices.filter { index in
        guard !isUndrawable(line[index]) else { return false }
        guard index > 0, isUndrawable(line[index - 1]), case .text(" ") = line[index].content else { return true }
        return false
    }.map { line[$0] }
}
