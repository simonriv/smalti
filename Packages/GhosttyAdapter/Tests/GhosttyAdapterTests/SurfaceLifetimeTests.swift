import AppKit
import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Integration tests with real libghostty surfaces (child process: `/bin/sleep`, no shell).
/// Review finding #3: the C callbacks must never reach a freed view, surface or app.
@MainActor
@Suite("Surface and runtime lifetime", .serialized)
struct SurfaceLifetimeTests {
    private let config: GhosttyConfig
    private let spec: TerminalSessionSpec

    init() throws {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: nil)
        config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-lifetime-\(UUID()).conf"))
        spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/sleep 30"))
    }

    @Test func viewReleasedWithoutShutDownLeavesNoLiveRegistration() throws {
        let runtime = try GhosttyRuntime(config: config)
        let before = GhosttyRuntime.liveViewCount

        try autoreleasepool {
            _ = try GhosttySurfaceView(app: runtime.app, spec: spec)
        }

        #expect(GhosttyRuntime.liveViewCount == before)
    }

    @Test func releasedRuntimeClearsTheAppSeenByWakeups() throws {
        do {
            let runtime = try GhosttyRuntime(config: config)
            #expect(GhosttyRuntime.currentApp == runtime.app)
        }

        #expect(GhosttyRuntime.currentApp == nil)
    }

    @Test func closeRequestedByLibghosttyIsDeferredToTheNextMainLoopTurn() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)

        view.requestClose()

        #expect(engine.view(for: pane) != nil, "closing inside the libghostty callback would free the view mid-keyDown")
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.view(for: pane) == nil)
    }

    @Test func eventForAReplacedSurfaceIsNotDelivered() throws {
        let runtime = try GhosttyRuntime(config: config)
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        defer { view.shutDown() }
        let viewAddress = Int(bitPattern: Unmanaged.passUnretained(view).toOpaque())
        let staleSurfaceAddress = 0x1234

        #expect(GhosttyRuntime.liveView(at: viewAddress, surfaceAddress: staleSurfaceAddress) == nil)
        #expect(GhosttyRuntime.liveView(at: viewAddress, surfaceAddress: view.surfaceAddress) === view)
    }
}
