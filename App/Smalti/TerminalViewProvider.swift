import AppKit
import GhosttyAdapter
import SmaltiCore

/// UI-side companion of the `TerminalEngine` port: the view that renders a pane.
/// Lives in the app so the domain never sees AppKit.
@MainActor
protocol TerminalViewProvider {
    func view(for pane: PaneID) -> NSView?
}

extension GhosttyTerminalEngine: TerminalViewProvider {}
