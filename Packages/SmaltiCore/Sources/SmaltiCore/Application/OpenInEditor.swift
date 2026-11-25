import Foundation

public enum EditorOutcome: Equatable, Sendable {
    /// An existing editor pane opened the file: focus it.
    case jumped(PaneID)
    /// No editor answered: open a pane beside `beside` running `command`, whose Neovim listens on `socket`.
    case opened(socket: String, command: String, beside: PaneID)
    case ignored
}

/// "Abrir en Neovim": the workspace's last focused Smalti Neovim jumps to the file and line; with none (or none that
/// answers), a new Neovim pane opens beside the pane it came from (spec F6).
@MainActor
public final class OpenInEditor {
    private let bridge: any EditorBridge
    private let panes: any EditorPanes
    private let socketDirectory: String
    private let nvim: String

    public init(bridge: any EditorBridge, panes: any EditorPanes, socketDirectory: String, nvim: String) {
        self.bridge = bridge
        self.panes = panes
        self.socketDirectory = socketDirectory
        self.nvim = nvim
    }

    public func open(_ target: EditorTarget, from pane: PaneID) async -> EditorOutcome {
        for editor in panes.editors(near: pane) {
            do {
                try await bridge.open(target, socket: editor.socket)
                return .jumped(editor.pane)
            } catch {
                continue
            }
        }
        guard let socket = try? EditorSocketPath.make(directory: socketDirectory, pane: PaneID()) else { return .ignored }
        return .opened(
            socket: socket, command: EditorCommand.launch(nvim: nvim, socket: socket, target: target), beside: pane)
    }
}
