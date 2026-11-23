import Foundation
import SmaltiCore

public actor FakeAgentTranscripts: AgentTranscripts {
    private var sessions: [SessionActivity]
    private var failure: TranscriptError?
    public private(set) var requestedSince: [Date] = []

    public init(sessions: [SessionActivity] = []) {
        self.sessions = sessions
    }

    public func fail(with error: TranscriptError) {
        failure = error
    }

    public func activity(since: Date) async throws(TranscriptError) -> TranscriptActivity {
        requestedSince.append(since)
        if let failure { throw failure }
        return TranscriptActivity(
            sessions: sessions.filter { ($0.lastActivity ?? .distantPast) >= since }, indexedSince: since)
    }
}

public struct FakeLiveAgents: LiveAgents {
    private let agents: [RunningAgent]

    public init(running: [RunningAgent] = []) {
        agents = running
    }

    public func running() async -> [RunningAgent] { agents }
}

public struct FakeLocalModels: LocalModels {
    private let report: LocalModelsReport

    public init(report: LocalModelsReport = .unavailable) {
        self.report = report
    }

    public func current() async -> LocalModelsReport { report }
}

@MainActor
public final class FakeSystemMetrics: SystemMetrics {
    public var next = SystemSample(
        cpu: .unavailable, gpu: .unavailable, memoryUsed: .unavailable, memoryTotal: 0, agentsMemory: .unavailable,
        pressure: .unavailable, machineName: "Mac")
    public private(set) var requestedProcesses: [[Int32]] = []

    public init() {}

    public func sample(agentProcesses: [Int32]) -> SystemSample {
        requestedProcesses.append(agentProcesses)
        return next
    }
}
