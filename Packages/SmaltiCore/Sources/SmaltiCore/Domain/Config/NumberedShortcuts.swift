/// The numbers that have a shortcut: ⌘1…⌘9 focus a pane, ⌃1…⌃9 go to a workspace. Panes and workspaces beyond the
/// last number exist but get no number (no shortcut, no "Ir al panel N" command, no index in the header).
public enum NumberedShortcuts {
    public static let range: ClosedRange<Int> = 1...9
}
