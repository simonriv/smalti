import Foundation
import SmaltiCore
import Testing

/// Every `AgentTranscripts` returns the sessions active since the date, becomes complete for it (an adapter may
/// index in steps: it gets `settlingCalls` reads to get there), and returns the same thing when nothing changed.
public enum AgentTranscriptsContract {
    public static let settlingCalls = 50

    public static func verify(_ transcripts: any AgentTranscripts, since: Date) async {
        do {
            var first = try await transcripts.activity(since: since)
            for _ in 1..<settlingCalls where first.indexedSince > since {
                first = try await transcripts.activity(since: since)
            }
            let second = try await transcripts.activity(since: since)
            #expect(first.indexedSince <= since, "a full read covers the asked period")
            #expect(first.sessions.allSatisfy { ($0.lastActivity ?? .distantPast) >= since }, "only active sessions")
            #expect(Set(first.sessions.map(\.sessionID)).count == first.sessions.count, "one entry per session")
            #expect(first == second, "an unchanged disk gives the same activity")
        } catch {
            Issue.record("a readable root must not fail: \(error)")
        }
    }
}

/// Every `LiveAgents` names processes that are alive and the sessions they run.
public enum LiveAgentsContract {
    public static func verify(_ live: any LiveAgents, isAlive: (Int32) -> Bool) async {
        let running = await live.running()
        #expect(running.allSatisfy { $0.pid > 0 && isAlive($0.pid) }, "every PID is a live process")
        #expect(running.allSatisfy { !$0.sessionID.isEmpty }, "every agent names its session")
    }
}

/// Every `LocalModels` is either unavailable or lists models with a size.
public enum LocalModelsContract {
    public static func verify(_ models: any LocalModels) async {
        guard case .available(let loaded, let onDisk) = await models.current() else { return }
        #expect((loaded + onDisk).allSatisfy { $0.bytes > 0 }, "listed models have a size")
        #expect(Set(loaded.map(\.name)).isDisjoint(with: onDisk.map(\.name)), "a loaded model is not repeated on disk")
    }
}
