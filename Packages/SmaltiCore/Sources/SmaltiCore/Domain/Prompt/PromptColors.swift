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
    var kept: [StyledRun] = []
    var skipsSpace = false
    for run in line {
        if case .icon(let icon) = run.content, icons.character(for: icon) == nil {
            skipsSpace = true
            continue
        }
        if skipsSpace, case .text(" ") = run.content {
            skipsSpace = false
            continue
        }
        skipsSpace = false
        kept.append(run)
    }
    return kept
}
