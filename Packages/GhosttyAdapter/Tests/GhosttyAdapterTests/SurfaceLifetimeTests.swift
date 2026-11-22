import AppKit
import Foundation
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
