extension Workspace {
    /// Status bar line, as in Main.dc.html: "solen · 3 paneles · dwindle".
    public var statusLine: String {
        let count = panes.count
        return "\(name) · \(count) \(count == 1 ? "panel" : "paneles") · \(layout.statusName)"
    }
}

/// What a pane header shows: the foreground process (or the title), the directory relative to home and the
/// shortcut `⌘1`…`⌘9` (the boards' `⌥N` is replaced: ⌥ types characters on the Latin American layout).
public struct PaneHeaderContent: Equatable, Sendable {
    public let process: String
    public let directory: String
    public let shortcut: String

    public init(process: String, directory: String, shortcut: String) {
        self.process = process
        self.directory = directory
        self.shortcut = shortcut
    }

    /// `index` is the pane's 1-based position when it has a shortcut (1…9), nil otherwise.
    public init(_ pane: Pane, index: Int?, keymap: Keymap, home: WorkingDirectory) {
        self.init(
            process: pane.headerName, directory: pane.workingDirectory.abbreviated(home: home),
            shortcut: index.flatMap { keymap.chord(for: .paneFocus($0))?.display } ?? "")
    }
}
