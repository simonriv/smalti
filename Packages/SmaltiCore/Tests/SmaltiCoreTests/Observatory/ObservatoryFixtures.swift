import Foundation
import SmaltiCore

/// Builders shared by the observatory report tests. Times are in Bogotá on 2026-11-18 unless a test says otherwise.
enum ObservatoryFixtures {
    static let opus = ModelID(rawValue: "claude-opus-5-5")
    static let haiku = ModelID(rawValue: "claude-haiku-5-5")
    static let home = "/Users/simon"

    static func calendar(_ zone: String = "America/Bogota") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    static func date(_ text: String, _ calendar: Calendar = calendar()) -> Date {
        let parts = text.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) }
        return calendar.date(
            from: DateComponents(
                year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4],
                second: parts.count > 5 ? parts[5] : 0)) ?? .distantPast
    }

    static func usage(input: Int = 0, output: Int = 0, cacheRead: Int = 0) -> TokenUsage {
        TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite5m: 0, cacheWrite1h: 0)
    }

    static func turn(
        _ id: String, at: Date, output: Int = 100, input: Int = 10, model: ModelID = opus, subagent: Bool = false
    ) -> TranscriptRecord {
        .assistantTurn(
            AssistantTurn(
                messageID: id, model: model, usage: usage(input: input, output: output), at: at, isSubagent: subagent))
    }

    static func session(_ id: String, cwd: String = "/Users/simon/dev/solen/api", _ records: [TranscriptRecord])
        -> SessionActivity
    {
        SessionActivity(sessionID: id).folding([.sessionInfo(sessionID: id, cwd: cwd, at: .distantPast)] + records)
    }

    static func running(_ id: String, pid: Int32 = 48_213, status: String = "busy", startedAt: Date) -> RunningAgent {
        RunningAgent(pid: pid, sessionID: id, cwd: "/Users/simon/dev/solen/api", status: status, startedAt: startedAt)
    }

    static let system = SystemSample(
        cpu: .value(31), gpu: .value(38), memoryUsed: .value(11_200_000_000), memoryTotal: 17_179_869_184,
        agentsMemory: .value(3_500_000_000), pressure: .value(.media), machineName: "MacBook Air M4")

    static func snapshot(
        sessions: [SessionActivity], running: [RunningAgent] = [], panes: [PaneAgent] = [],
        localModels: LocalModelsReport = .unavailable, system: SystemSample = system, now: Date,
        indexedSince: Date = .distantPast
    ) -> ObservatorySnapshot {
        ObservatorySnapshot(
            activity: TranscriptActivity(sessions: sessions, indexedSince: indexedSince), running: running,
            panes: panes, localModels: localModels, system: system, cpuHistory: [], gpuHistory: [],
            catalog: .standard, now: now, home: home, lastError: nil)
    }

    static func paneAgent(_ id: String, state: AgentState, label: String = "solen/api", startedAt: Date) -> PaneAgent {
        PaneAgent(
            pane: PaneID(rawValue: UUID()), label: label,
            session: AgentSession(harness: .claude, sessionID: id, title: nil, state: state, startedAt: startedAt))
    }
}
