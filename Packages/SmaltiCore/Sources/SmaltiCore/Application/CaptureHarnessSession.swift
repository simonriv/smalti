import Foundation

/// How a pane's session is decided when its harness starts.
public enum CaptureDecision: Equatable, Sendable {
    /// Named already: by a pending restore or search, or on the command line (`codex resume <id>`).
    case known(String)
    /// The pane continues the directory's last session (`agy -c`): no search, whatever it resumes is not ours to
    /// name (review 1, C1).
    case continuing
    /// Look for the session the harness creates.
    case search
}

/// What to capture for a pane whose foreground process became a harness.
public struct CaptureStart: Equatable, Sendable {
    public let pane: PaneID
    public let harness: HarnessID
    public let directory: String
    public let processStartedAt: Date
    public let pid: Int32?
    public let decision: CaptureDecision

    public init(
        pane: PaneID, harness: HarnessID, directory: String, processStartedAt: Date, pid: Int32?,
        decision: CaptureDecision
    ) {
        self.pane = pane
        self.harness = harness
        self.directory = directory
        self.processStartedAt = processStartedAt
        self.pid = pid
        self.decision = decision
    }

    /// The pane's binding while the capture runs: the harness is known at once, so a session saved meanwhile
    /// relaunches it (with its id when named, else as "la última del directorio").
    public var interimBinding: HarnessBinding {
        let id: String? = if case .known(let id) = decision { id } else { nil }
        return HarnessBinding(harness: harness, sessionID: id, processStartedAt: processStartedAt, pid: pid)
    }
}

/// Finds the session a harness writes in a pane by looking at its store, retrying while the session is not there
/// yet (harnesses create it with the first message). Spec F6, "Captura del ID", with review 1's rule: when another
/// pane of the same harness and directory is also waiting, no pane gets an id (timestamps cannot tell them apart),
/// so each falls back to "la última del directorio" instead of resuming another pane's conversation.
/// What a capture asks the panes around it, each time it looks: how many others of the same harness and directory still
/// wait (`competitors`), which ids are taken (`claimed`), whether its process still runs, and where to report a session
/// it gave up because another pane competed for it (`disputed`, final review C1).
public struct CaptureContext {
    let competitors: () -> Int
    let claimed: () -> Set<String>
    let isStillRunning: () -> Bool
    let disputed: (String) -> Void

    public init(
        competitors: @escaping () -> Int, claimed: @escaping () -> Set<String>,
        isStillRunning: @escaping () -> Bool, disputed: @escaping (String) -> Void
    ) {
        self.competitors = competitors
        self.claimed = claimed
        self.isStillRunning = isStillRunning
        self.disputed = disputed
    }
}

@MainActor
public final class CaptureHarnessSession {
    public static let retryEvery: Duration = .seconds(2)
    public static let giveUpAfter: TimeInterval = 600

    private let registry: HarnessRegistry
    private let clock: () -> Date
    private let sleep: (Duration) async -> Void
    private let resolve: (String) -> String

    /// `resolve` turns the pane's directory into the path the harness records (`realpath`), done by the app.
    public init(
        registry: HarnessRegistry, clock: @escaping () -> Date, sleep: @escaping (Duration) async -> Void,
        resolve: @escaping (String) -> String = { $0 }
    ) {
        self.registry = registry
        self.clock = clock
        self.sleep = sleep
        self.resolve = resolve
    }

    /// Nil when the process is no harness, or when its hooks already name the session (Claude).
    public func processChanged(in pane: Pane, to process: ForegroundProcess) -> CaptureStart? {
        guard let adapter = registry.adapter(detecting: process), pane.agent?.harness != adapter.harness else {
            return nil
        }
        return CaptureStart(
            pane: pane.id, harness: adapter.harness, directory: resolve(pane.workingDirectory.path),
            processStartedAt: process.startedAt ?? clock(), pid: process.pid,
            decision: decision(for: pane, process, adapter))
    }

    private func decision(for pane: Pane, _ process: ForegroundProcess, _ adapter: any HarnessAdapter)
        -> CaptureDecision
    {
        if let pending = pane.harnessBinding, pending.isPending, pending.harness == adapter.harness {
            return pending.sessionID.map(CaptureDecision.known) ?? .continuing
        }
        return adapter.sessionID(fromCommandLine: process.commandLine ?? []).map(CaptureDecision.known) ?? .search
    }

    /// The binding for the process: with the session found, or without an id (the fallback) when another pane
    /// competes, the store cannot be read or ten minutes pass. Nil only if the process leaves first.
    public func capture(_ start: CaptureStart, _ context: CaptureContext) async -> HarnessBinding? {
        switch start.decision {
        case .known(let id): return binding(start, id)
        case .continuing: return binding(start, nil)
        case .search: return await search(start, context)
        }
    }

    private func search(_ start: CaptureStart, _ context: CaptureContext) async -> HarnessBinding? {
        guard let adapter = registry.adapter(for: start.harness) else { return binding(start, nil) }
        let deadline = start.processStartedAt.addingTimeInterval(Self.giveUpAfter)
        while clock() < deadline {
            guard context.isStillRunning() else { return nil }
            let window = CaptureWindow(
                directory: start.directory, processStartedAt: start.processStartedAt, excludedIDs: context.claimed())
            do {
                if let found = try await adapter.captureSessionId(in: window) {
                    guard context.competitors() == 0 else {
                        // Nobody may take it later: the pane that searches next would see no competitor left.
                        context.disputed(found)
                        return binding(start, nil)
                    }
                    return binding(start, found)
                }
            } catch {
                if case .storeMissing = error { return binding(start, nil) }
                if case .unknownSchema = error { return binding(start, nil) }
            }
            await sleep(Self.retryEvery)
        }
        return binding(start, nil)
    }

    private func binding(_ start: CaptureStart, _ id: String?) -> HarnessBinding {
        HarnessBinding(harness: start.harness, sessionID: id, processStartedAt: start.processStartedAt, pid: start.pid)
    }
}
