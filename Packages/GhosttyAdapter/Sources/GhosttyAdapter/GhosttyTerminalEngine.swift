import AppKit
import GhosttyKit
import SmaltiCore

/// `TerminalEngine` backed by libghostty: one `GhosttySurfaceView` per pane.
@MainActor
public final class GhosttyTerminalEngine: TerminalEngine {
    private let runtime: GhosttyRuntime
    private var views: [PaneID: GhosttySurfaceView] = [:]

    public init(runtime: GhosttyRuntime) {
        self.runtime = runtime
    }

    public func open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError) {
        views[pane] = try GhosttySurfaceView(app: runtime.app, spec: spec)
    }

    public func close(_ pane: PaneID) {
        guard let view = views.removeValue(forKey: pane) else { return }
        view.shutDown()
        view.removeFromSuperview()
    }

    public func show(_ pane: PaneID) {
        views[pane]?.show()
    }

    public func hide(_ pane: PaneID) {
        views[pane]?.hide()
    }

    public func events(for pane: PaneID) -> AsyncStream<TerminalEvent> {
        views[pane]?.events ?? AsyncStream { $0.finish() }
    }

    /// The AppKit view that renders `pane`; the app embeds it. Not part of the domain port.
    public func view(for pane: PaneID) -> NSView? {
        views[pane]
    }
}
