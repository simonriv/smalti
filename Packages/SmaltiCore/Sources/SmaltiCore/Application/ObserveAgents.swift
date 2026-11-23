import Foundation

@MainActor
public struct ObservatorySources {
    public let transcripts: any AgentTranscripts
    public let live: any LiveAgents
    public let localModels: any LocalModels
    public let system: any SystemMetrics
    public let catalog: ModelCatalog
    public let home: String

    public init(
        transcripts: any AgentTranscripts, live: any LiveAgents, localModels: any LocalModels,
        system: any SystemMetrics, catalog: ModelCatalog, home: String
    ) {
        self.transcripts = transcripts
        self.live = live
        self.localModels = localModels
        self.system = system
        self.catalog = catalog
        self.home = home
    }
}

/// Gathers one refresh's worth of facts. It always asks for 30 days: with the index up to date that costs the same
/// as today, and the status bar needs today while the screen shows another period.
@MainActor
public final class ObserveAgents {
    private let sources: ObservatorySources
    private var lastActivity = TranscriptActivity(sessions: [], indexedSince: .distantFuture)
    private var cpuHistory: [Double] = []
    private var gpuHistory: [Double] = []
    /// `status` values the session registry wrote that Smalti does not know; the app logs each once.
    public private(set) var unknownStatuses: Set<String> = []

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
        unknownStatuses.formUnion(ObservedSession.unknownStatuses(in: running))
        let system = sources.system.sample(agentProcesses: running.map(\.pid))
        record(system)
        return ObservatorySnapshot(
            activity: lastActivity, running: running, panes: panes, localModels: await sources.localModels.current(),
            system: system, cpuHistory: cpuHistory, gpuHistory: gpuHistory, catalog: sources.catalog, now: now,
            home: sources.home, lastError: lastError)
    }

    private func record(_ sample: SystemSample) {
        if let cpu = sample.cpu.value { cpuHistory = Array((cpuHistory + [cpu]).suffix(Self.samplesKept)) }
        if let gpu = sample.gpu.value { gpuHistory = Array((gpuHistory + [gpu]).suffix(Self.samplesKept)) }
    }
}
