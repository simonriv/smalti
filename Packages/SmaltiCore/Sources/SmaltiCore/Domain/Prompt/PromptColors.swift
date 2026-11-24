extension Theme {
    /// The theme's color for a segment's role, after protection (the applied theme's palette and text).
    func color(for role: SegmentColor) -> RGBAColor {
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
