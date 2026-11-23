import Foundation
import OSLog
import SmaltiCore

/// One refresh, ready to paint: the snapshot and what the status bar and the headers show, all computed off the main
/// thread (C11: a refresh never blocks it more than 16 ms).
struct ObservatoryFrame: Sendable {
    let snapshot: ObservatorySnapshot
    let statusFigures: StatusFigures
    let paneDetails: [String: PaneAgentDetail]

    static func make(_ snapshot: ObservatorySnapshot) -> ObservatoryFrame {
        let sessions = snapshot.panes.map(\.session.sessionID)
        return ObservatoryFrame(
            snapshot: snapshot, statusFigures: StatusFigures.make(snapshot, calendar: .autoupdatingCurrent),
            paneDetails: Dictionary(
                sessions.map { ($0, PaneAgentDetail.make(sessionID: $0, snapshot: snapshot)) }, uniquingKeysWith: { $1 }
            ))
    }
}

/// Primary adapter that keeps the observatory's snapshot fresh: every 2 s while the observatory is open, every 10 s
/// otherwise (status bar and headers), right away after the hooks that change tokens, and samples the machine every
/// 2 s on its own. Refreshes never overlap: one asked for during another runs once, after it.
@MainActor
final class ObservatoryRefresher {
    private let observe: ObserveAgents
    private let panes: () -> [PaneAgent]
    private let onSnapshot: (ObservatoryFrame) -> Void
    private let onError: (String) -> Void
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "observatory")
    private var isRefreshing = false
    private var isQueued = false
    private var refreshLoop: Task<Void, Never>?
    private var samplingLoop: Task<Void, Never>?
    private var loggedStatuses: Set<String> = []
    private var lastError: String?

    static let openInterval: Duration = .seconds(2)
    static let closedInterval: Duration = .seconds(10)
    static let samplingInterval: Duration = .seconds(2)
    /// Hooks after which a session's tokens or context changed.
    static let refreshingHooks: Set<AgentHook> = [.stop, .postToolUse, .sessionStart]

    var isObservatoryOpen = false {
        didSet { if isObservatoryOpen && !oldValue { refreshNow() } }
    }

    struct Callbacks {
        let panes: () -> [PaneAgent]
        let onSnapshot: (ObservatoryFrame) -> Void
        /// A refresh could not read the transcripts; called once per distinct message.
        let onError: (String) -> Void
    }

    init(observe: ObserveAgents, callbacks: Callbacks) {
        self.observe = observe
        panes = callbacks.panes
        onSnapshot = callbacks.onSnapshot
        onError = callbacks.onError
    }

    func start() {
        samplingLoop = Task { [weak self] in
            while !Task.isCancelled {
                self?.observe.sampleSystem()
                try? await Task.sleep(for: Self.samplingInterval)
            }
        }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.refreshAndNextInterval() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Refreshes and says how long to wait, so the loop holds no reference to `self` while it sleeps.
    private func refreshAndNextInterval() -> Duration {
        refreshNow()
        return isObservatoryOpen ? Self.openInterval : Self.closedInterval
    }

    func stop() {
        samplingLoop?.cancel()
        refreshLoop?.cancel()
    }

    func agentEvent(_ event: AgentEvent) {
        if Self.refreshingHooks.contains(event.hook) { refreshNow() }
    }

    func refreshNow() {
        guard !isRefreshing else {
            isQueued = true
            return
        }
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.observe.snapshot(panes: self.panes(), now: .now)
            let frame = await Task.detached(priority: .utility) { ObservatoryFrame.make(snapshot) }.value
            self.deliver(frame)
            self.isRefreshing = false
            if self.isQueued {
                self.isQueued = false
                self.refreshNow()
            }
        }
    }

    private func deliver(_ frame: ObservatoryFrame) {
        let snapshot = frame.snapshot
        for status in observe.unknownStatuses.subtracting(loggedStatuses) {
            logger.notice("unknown Claude session status \(status, privacy: .public): shown as working")
            loggedStatuses.insert(status)
        }
        if let error = snapshot.lastError, error != lastError { onError(error) }
        lastError = snapshot.lastError
        onSnapshot(frame)
    }
}
