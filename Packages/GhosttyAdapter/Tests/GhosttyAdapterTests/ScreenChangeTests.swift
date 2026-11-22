import AppKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Review finding #2 (plan Review Focus 5): moving to another screen updates libghostty's display (vsync)
/// and content scale, as Ghostty does, because viewDidChangeBackingProperties alone is not enough.
@MainActor
@Suite("Screen change", .serialized)
struct ScreenChangeTests {
    private let runtime: GhosttyRuntime
    private let spec: TerminalSessionSpec

    init() throws {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: nil)
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-screen-\(UUID()).conf"))
        runtime = try GhosttyRuntime(config: config)
        spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/sleep 30"))
    }

    private func windowHosting(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    @Test func joiningAWindowAppliesThatScreensDisplay() throws {
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        defer { view.shutDown() }
        let window = windowHosting(view)
        let screen = try #require(window.screen)

        #expect(view.appliedDisplayID == screen.displayID)
    }

    @Test func screenChangeReappliesTheDisplay() throws {
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        defer { view.shutDown() }
        let window = windowHosting(view)
        let before = view.displayUpdates

        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)

        #expect(view.displayUpdates == before + 1)
    }
}
