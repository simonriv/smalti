/// How the processes and ports views name a pane: its workspace and its number there, "web · 2".
public enum PaneNames {
    public static func of(_ windows: WindowSet, texts: ProcessTexts) -> [PaneID: String] {
        var names: [PaneID: String] = [:]
        for window in windows.windows {
            for workspace in window.workspaces.workspaces {
                for (index, pane) in workspace.panes.enumerated() {
                    names[pane.id] = texts.paneName(["workspace": workspace.name, "number": String(index + 1)])
                }
            }
        }
        return names
    }
}
