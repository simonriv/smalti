/// Something Smalti asks a pane's terminal to do (F4.5): the basic commands every terminal has.
public enum TerminalAction: Equatable, Sendable {
    case copy
    case paste
    case selectAll
    /// Clears the screen and the scrollback.
    case clear
    case scroll(ScrollTarget)
    /// Jumps to the previous or next shell prompt (OSC 133).
    case jumpToPrompt(PromptDirection)
}

public enum ScrollTarget: Equatable, Sendable {
    case pageUp, pageDown, top, bottom
}

public enum PromptDirection: Equatable, Sendable {
    case previous, next
}

/// Which way to move through the matches of a scrollback search.
public enum SearchDirection: Equatable, Sendable {
    case previous, next
}
