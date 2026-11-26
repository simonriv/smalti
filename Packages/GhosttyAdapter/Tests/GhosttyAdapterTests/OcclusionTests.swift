import AppKit
import GhosttyKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// R7: hidden panes are occluded (libghostty pauses their rendering) and stop polling their foreground process.
@MainActor
@Suite("Surface occlusion", .serialized)
struct OcclusionTests {
    private let engine: GhosttyTerminalEngine
    private let spec: TerminalSessionSpec

    init() throws {
        try TestGhostty.initialize()
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-occlusion-\(UUID()).conf"))
        engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config, texts: .spanish))
        spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f"))
    }

    @Test func openedSurfaceStartsVisibleAndPolling() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }

        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        #expect(view.isVisible)
        #expect(view.isPollingForegroundProcess)
    }

    @Test func hideMarksSurfaceOccluded() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        engine.hide(pane)

        #expect(!view.isVisible)
        #expect(!view.isPollingForegroundProcess)
    }

    @Test func showMarksSurfaceVisible() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        engine.hide(pane)

        engine.show(pane)

        #expect(view.isVisible)
        #expect(view.isPollingForegroundProcess)
    }

    /// Final review (minor 2): closing asks what runs now, even in a hidden pane that no longer polls. A program
    /// started from the shell leads its own process group, so it is the one named.
    @Test func hiddenPaneStillTellsItsForegroundProcessWhenAsked() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        #expect(wait { (view.surface.map(ghostty_surface_foreground_pid) ?? 0) > 0 })
        try type("sleep 30\r", into: view)
        engine.hide(pane)

        #expect(wait { engine.foregroundProcess(of: pane)?.name == "sleep" })
        #expect(engine.foregroundProcess(of: pane)?.commandLine == ["sleep", "30"])
    }

    private func wait(_ condition: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func type(_ text: String, into view: GhosttySurfaceView) throws {
        let surface = try #require(view.surface)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        text.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    @Test func shutDownStopsPolling() throws {
        let pane = try engine.open(spec)
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        engine.close(pane)

        #expect(!view.isPollingForegroundProcess)
    }

    @Test func becomingFirstResponderGivesTheSurfaceEngineFocus() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let window = Self.window(holding: view)

        window.makeFirstResponder(view)

        #expect(view.hasEngineFocus)
    }

    /// A hidden pane may still be the window's first responder; libghostty must not think it is focused.
    @Test func hideClearsEngineFocus() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let window = Self.window(holding: view)
        window.makeFirstResponder(view)

        engine.hide(pane)

        #expect(!view.hasEngineFocus)
    }

    /// Shown again while still the first responder: AppKit sends no new `becomeFirstResponder`, so `show` refocuses.
    @Test func showRestoresEngineFocusOfTheFirstResponder() throws {
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let window = Self.window(holding: view)
        window.makeFirstResponder(view)
        engine.hide(pane)

        engine.show(pane)

        #expect(view.hasEngineFocus)
    }

    private static func window(holding view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        return window
    }
}
