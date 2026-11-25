import Foundation

/// Port: an editor reached by its socket (Neovim). The editor's view lives in a pane like any program.
@MainActor
public protocol EditorBridge: AnyObject, Sendable {
    /// Opens `target` in the editor listening on `socket`, at its line.
    func open(_ target: EditorTarget, socket: String) async throws(EditorError)
    /// The file and line the editor shows, for saving the session; nil when it does not answer in time.
    func current(socket: String) async -> EditorPosition?
}

/// What the app knows about its editor panes: those near `pane` (its workspace), the last focused first.
@MainActor
public protocol EditorPanes: AnyObject {
    func editors(near pane: PaneID) -> [(pane: PaneID, socket: String)]
}
