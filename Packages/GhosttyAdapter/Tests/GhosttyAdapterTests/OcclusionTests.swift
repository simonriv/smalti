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
        try GhosttyProcess.ensureInitialized(resourcesDirectory: nil)
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-occlusion-\(UUID()).conf"))
        engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
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

    @Test func shutDownStopsPolling() throws {
        let pane = try engine.open(spec)
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        engine.close(pane)

        #expect(!view.isPollingForegroundProcess)
    }
}
