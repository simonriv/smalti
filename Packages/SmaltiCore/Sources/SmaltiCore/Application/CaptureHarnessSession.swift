import Foundation

/// What to capture for a pane whose foreground process became a harness. `decided` is the id already known (the
/// pane was restored or opened from the search) or named on the command line (`codex resume <id>`).
public struct CaptureStart: Equatable, Sendable {
    public let pane: PaneID
    public let harness: HarnessID
    public let directory: String
    public let processStartedAt: Date
    public let decided: String?
}

/// Finds the session a harness writes in a pane by looking at its store, retrying while the session is not there
/// yet (harnesses create it with the first message). Spec F6, "Captura del ID".
@MainActor
public final class CaptureHarnessSession {
    public static let retryEvery: Duration = .seconds(2)
    public static let giveUpAfter: TimeInterval = 600

    private let registry: HarnessRegistry
    private let clock: () -> Date
    private let sleep: (Duration) async -> Void

    public init(registry: HarnessRegistry, clock: @escaping () -> Date, sleep: @escaping (Duration) async -> Void) {
        self.registry = registry
        self.clock = clock
        self.sleep = sleep
    }

    /// Nil when the process is no harness, or when its hooks already name the session (Claude).
    public func processChanged(in pane: Pane, to process: ForegroundProcess, knownID: String?) -> CaptureStart? {
        guard let adapter = registry.adapter(detecting: process), pane.agent?.harness != adapter.harness else {
            return nil
        }
        let named = knownID ?? adapter.sessionID(fromCommandLine: process.commandLine ?? [])
        return CaptureStart(
            pane: pane.id, harness: adapter.harness, directory: pane.workingDirectory.path,
            processStartedAt: process.startedAt ?? clock(), decided: named)
    }

    /// The binding once the session is found; nil if the process leaves first or ten minutes pass. `claimed` gives
    /// the ids other panes hold now; `laterStarts`, when other panes of the same harness and directory started.
    public func capture(
        _ start: CaptureStart, laterStarts: [Date] = [], claimed: () -> Set<String>, isStillRunning: () -> Bool
    ) async -> HarnessBinding? {
        if let decided = start.decided { return binding(start, decided) }
        guard let adapter = registry.adapter(for: start.harness) else { return nil }
        let deadline = start.processStartedAt.addingTimeInterval(Self.giveUpAfter)
        while clock() < deadline, isStillRunning() {
            let window = CaptureWindow(
                directory: start.directory, processStartedAt: start.processStartedAt, excludedIDs: claimed(),
                laterStarts: laterStarts)
            if let found = try? await adapter.captureSessionId(in: window) { return binding(start, found) }
            await sleep(Self.retryEvery)
        }
        return nil
    }

    private func binding(_ start: CaptureStart, _ id: String) -> HarnessBinding {
        HarnessBinding(harness: start.harness, sessionID: id, processStartedAt: start.processStartedAt)
    }
}
