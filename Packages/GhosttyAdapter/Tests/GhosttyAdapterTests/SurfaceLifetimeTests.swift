import AppKit
import Foundation
import GhosttyKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Integration tests with real libghostty surfaces (child process: `/bin/zsh -f`, no startup files).
/// Review finding #3: the C callbacks must never reach a freed view, surface or app. R4: one close path, through
/// the app; the engine only raises requests.
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
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f"))
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

    @Test func closeSurfaceWithLiveProcessRequestsClose() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let events = engine.events(for: pane)

        view.requestClose()

        #expect(await Self.firstEvent(in: events) { $0 == .closeRequested } == .closeRequested)
        #expect(engine.view(for: pane) != nil, "only the app closes panes (ClosePane)")
    }

    @Test func closeRequestIsDeferredToTheNextMainLoopTurn() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let events = engine.events(for: pane)

        view.requestClose()
        engine.close(pane)

        #expect(await Self.collect(events).isEmpty, "a request raised inside a libghostty call must wait a turn")
    }

    @Test func closeEmitsNoExitedEvent() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        let events = engine.events(for: pane)

        engine.close(pane)

        let received = await Self.collect(events)
        #expect(!received.contains { if case .exited = $0 { true } else { false } })
    }

    @Test func childExitIsDeliveredOnceWithItsCode() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let view = try #require(engine.view(for: pane) as? GhosttySurfaceView)
        let events = engine.events(for: pane)

        view.deliver(.exited(code: 3))
        view.deliver(.exited(code: 3))
        try await Task.sleep(for: .milliseconds(50))
        engine.close(pane)

        let exits = await Self.collect(events).filter { if case .exited = $0 { true } else { false } }
        #expect(exits == [.exited(code: 3)])
    }

    /// Under `abnormal-command-exit-runtime` (250 ms) libghostty sends only SHOW_CHILD_EXITED, never close_surface.
    @Test func abnormalEarlyExitDeliversOneExited() async throws {
        let exits = try await exitsDelivered(running: "/bin/zsh -f -c 'exit 3'")

        // macOS may report the code as 0 (Surface.zig:1304), so only the count is asserted.
        #expect(exits.count == 1)
    }

    /// A normal exit goes through SHOW_CHILD_EXITED and then close_surface_cb with process_exited. A surface-level
    /// command forces `wait-after-command` (embedded.zig:572), which skips close_surface_cb, so the command comes
    /// from the config's `command` key instead and the surface passes none. It is still `zsh -f`, never a login
    /// shell.
    @Test func normalExitThroughBothCallbacksDeliversOneExited() async throws {
        let configWithCommand = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal) + "command = /bin/zsh -f -c 'sleep 0.4; exit 3'\n",
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-exit-\(UUID()).conf"))

        let exits = try await exitsDelivered(
            TerminalSessionSpec(workingDirectory: spec.workingDirectory, command: .loginShell),
            config: configWithCommand)

        #expect(exits.count == 1)
    }

    /// A surface-level command waits after exiting, so only SHOW_CHILD_EXITED reports the exit.
    @Test func customCommandExitDeliversOneExited() async throws {
        let exits = try await exitsDelivered(running: "/bin/zsh -f -c 'sleep 0.4; exit 3'")

        #expect(exits.count == 1)
    }

    @Test func visibleSurfaceReportsItsForegroundProcess() async throws {
        let engine = GhosttyTerminalEngine(runtime: try GhosttyRuntime(config: config))
        let pane = try engine.open(spec)
        defer { engine.close(pane) }
        let events = engine.events(for: pane)

        let event = await Self.firstEvent(in: events, within: .seconds(4)) {
            if case .foregroundProcessChanged = $0 { true } else { false }
        }

        #expect(event == .foregroundProcessChanged("zsh"))
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

    /// Runs a real surface and returns every `.exited` seen until the exit is due plus a grace period.
    private func exitsDelivered(running command: String) async throws -> [TerminalEvent] {
        try await exitsDelivered(
            TerminalSessionSpec(workingDirectory: spec.workingDirectory, command: .custom(command)), config: config)
    }

    private func exitsDelivered(_ session: TerminalSessionSpec, config: GhosttyConfig) async throws -> [TerminalEvent] {
        let runtime = try GhosttyRuntime(config: config)
        let engine = GhosttyTerminalEngine(runtime: runtime)
        let pane = try engine.open(session)
        defer { engine.close(pane) }
        let events = engine.events(for: pane)
        let collector = Task {
            var exits: [TerminalEvent] = []
            for await event in events {
                if case .exited = event { exits.append(event) }
            }
            return exits
        }
        // Wakeups tick only the most recent runtime, and other suites create runtimes in parallel; ticking this
        // app here is exactly what its wakeups would do.
        let deadline = ContinuousClock.now + Self.exitTimeout + Self.exitGracePeriod
        while ContinuousClock.now < deadline {
            ghostty_app_tick(runtime.app)
            try await Task.sleep(for: .milliseconds(20))
        }
        collector.cancel()
        return await collector.value
    }

    private static let exitTimeout: Duration = .seconds(2)
    private static let exitGracePeriod: Duration = .milliseconds(500)

    private static func collect(_ events: AsyncStream<TerminalEvent>) async -> [TerminalEvent] {
        var received: [TerminalEvent] = []
        for await event in events { received.append(event) }
        return received
    }

    private static func firstEvent(
        in events: AsyncStream<TerminalEvent>, within limit: Duration = .seconds(2),
        where matches: @escaping @Sendable (TerminalEvent) -> Bool
    ) async -> TerminalEvent? {
        let search = Task {
            for await event in events where matches(event) { return Optional(event) }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: limit)
            search.cancel()
        }
        defer { timeout.cancel() }
        return await search.value
    }
}
