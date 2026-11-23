import AppKit
import GhosttyAdapter
import SmaltiCore

/// UI-side companion of the `TerminalEngine` port: the view that renders a pane.
/// Lives in the app so the domain never sees AppKit.
@MainActor
protocol TerminalViewProvider {
    func view(for pane: PaneID) -> NSView?
    /// F4: menus open only at the shell prompt and close when it is left.
    func isAtPrompt(_ pane: PaneID) -> Bool
    func cursorCell(_ pane: PaneID) -> Rect?
    /// ⌘↩ in the history palette: Return typed into the pane after Smalti's `edit`.
    func pressReturn(_ pane: PaneID)
}

extension GhosttyTerminalEngine: TerminalViewProvider {}
