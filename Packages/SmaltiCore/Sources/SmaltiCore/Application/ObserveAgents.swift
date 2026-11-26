import Foundation

@MainActor
public struct ObservatorySources {
    public let transcripts: any AgentTranscripts
    public let live: any LiveAgents
    public let localModels: any LocalModels
    public let system: any SystemMetrics
    public let catalog: ModelCatalog
    public let home: String
    /// F6: other harnesses' token use (OpenCode).
    public let usage: [any HarnessUsage]

    public init(
        transcripts: any AgentTranscripts, live: any LiveAgents, localModels: any LocalModels,
        system: any SystemMetrics, catalog: ModelCatalog, home: String, usage: [any HarnessUsage] = []
    ) {
        self.transcripts = transcripts
        self.live = live
        self.localModels = localModels
        self.system = system
        self.catalog = catalog
        self.home = home
        self.usage = usage
    }
}

/// Gathers one refresh's worth of facts. It always asks for 30 days: with the index up to date that costs the same
/// as today, and the status bar needs today while the screen shows another period. The machine is sampled apart,
/// every 2 s, so its curves keep a steady rhythm whatever the refreshes do.
@MainActor
public final class ObserveAgents {
    private let sources: ObservatorySources
    private var lastActivity = TranscriptActivity(sessions: [], indexedSince: .distantFuture)
    private var lastRunning: [RunningAgent] = []
    private var lastSample: SystemSample?
    private var cpuHistory: [Double] = []
    private var gpuHistory: [Double] = []
    /// `status` values the session registry wrote that Smalti does not know; the app logs each once.
    public private(set) var unknownStatuses: Set<String> = []
    /// F6: why another harness's usage could not be read, each reason once; the app logs them.
    public private(set) var usageFailures: [String] = []

    public static let history: TimeInterval = 30 * 86_400
    public static let samplesKept = 60

    public init(_ sources: ObservatorySources) {
        self.sources = sources
    }

    public func snapshot(panes: [PaneAgent], now: Date) async -> ObservatorySnapshot {
        var lastError: String?
        do {
            lastActivity = try await sources.transcripts.activity(since: now.addingTimeInterval(-Self.history))
        } catch {
            lastError = error.message
        }
        let running = await sources.live.running()
        lastRunning = running
        unknownStatuses.formUnion(ObservedSession.unknownStatuses(in: running))
        let system = lastSample ?? sampleSystem()
        let snapshot = ObservatorySnapshot(
            activity: lastActivity, running: running, panes: panes, localModels: await sources.localModels.current(),
            system: system, cpuHistory: cpuHistory, gpuHistory: gpuHistory, catalog: sources.catalog, now: now,
            home: sources.home, lastError: lastError)
        return snapshot.adding(usage: await otherUsage(since: now.addingTimeInterval(-Self.history)))
    }

    /// Each harness's sessions; one that cannot be read adds nothing and never hides Claude's.
    private func otherUsage(since: Date) async -> [UsageRow] {
        var rows: [UsageRow] = []
        for source in sources.usage {
            do {
                rows += try await source.sessions(since: since)
            } catch {
                // Only the log reads these; logs are in English whatever the interface's language.
                let message = error.message(.english)
                if !usageFailures.contains(message) { usageFailures.append(message) }
            }
        }
        return rows
    }

    /// One reading of the machine, on its own 2 s rhythm; refreshes reuse the latest one.
    @discardableResult
    public func sampleSystem() -> SystemSample {
        let sample = sources.system.sample(agentProcesses: lastRunning.map(\.pid))
        lastSample = sample
        record(sample)
        return sample
    }

    private func record(_ sample: SystemSample) {
        if let cpu = sample.cpu.value { cpuHistory = Array((cpuHistory + [cpu]).suffix(Self.samplesKept)) }
        if let gpu = sample.gpu.value { gpuHistory = Array((gpuHistory + [gpu]).suffix(Self.samplesKept)) }
    }
}
