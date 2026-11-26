/// Keeps the processes and ports views fresh, and only them: it reads nothing until `start` and nothing after
/// `stop` (spec F8, C4). The first refresh is immediate, the second comes `first` later (it gives CPU) and then one
/// every `every`. Refreshes never overlap.
@MainActor
public final class ProcessesRefresher {
    public struct Timing: Sendable {
        public let first: Duration
        public let every: Duration

        public init(first: Duration, every: Duration) {
            self.first = first
            self.every = every
        }

        public static let standard = Timing(first: .seconds(1), every: .seconds(2))
    }

    private let observe: ObserveProcesses
    private let timing: Timing
    private var loop: Task<Void, Never>?
    private var isRefreshing = false
    /// Bumped by every start and stop: a read under way for an older run delivers nothing and blocks nothing.
    private var generation = 0
    private var foregroundGroups: () -> [PaneID: Int32] = { [:] }
    private var deliver: (ProcessesSnapshot) -> Void = { _ in }

    public init(observe: ObserveProcesses, timing: Timing) {
        self.observe = observe
        self.timing = timing
    }

    public var isRunning: Bool { loop != nil }

    public func start(
        foregroundGroups: @escaping () -> [PaneID: Int32], onSnapshot: @escaping (ProcessesSnapshot) -> Void
    ) {
        if loop != nil { stop() }
        self.foregroundGroups = foregroundGroups
        deliver = onSnapshot
        let timing = timing
        loop = Task { [weak self] in
            await self?.refreshNow()
            try? await Task.sleep(for: timing.first)
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: timing.every)
            }
        }
    }

    /// Stops reading and forgets the last sample: the next start begins without CPU, not with a delta across the
    /// time the view was closed.
    public func stop() {
        loop?.cancel()
        loop = nil
        generation += 1
        isRefreshing = false
        observe.reset()
    }

    /// One refresh now (after an action), if running and none is under way.
    public func refreshNow() async {
        guard loop != nil, !isRefreshing else { return }
        let run = generation
        isRefreshing = true
        let snapshot = await observe.refresh(foregroundGroups: foregroundGroups())
        guard run == generation else { return }
        isRefreshing = false
        deliver(snapshot)
    }
}
