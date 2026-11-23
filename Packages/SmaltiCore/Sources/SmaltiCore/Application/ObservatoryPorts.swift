import Foundation

public enum TranscriptError: Error, Equatable, Sendable {
    case unreadableRoot(path: String, reason: String)

    /// The status-bar text when a refresh could not read the transcripts.
    public var message: String {
        switch self {
        case .unreadableRoot(let path, let reason): "No se pudieron leer los transcripts de \(path): \(reason)"
        }
    }
}

/// Port: the coding agents' history on disk, already folded per session.
public protocol AgentTranscripts: Sendable {
    /// Sessions with activity since `since`, up to date with what is on disk now.
    func activity(since: Date) async throws(TranscriptError) -> TranscriptActivity
}

/// Port: the agents running on this machine right now.
public protocol LiveAgents: Sendable {
    func running() async -> [RunningAgent]
}

/// Port: local models (Ollama) loaded in memory or kept on disk.
public protocol LocalModels: Sendable {
    func current() async -> LocalModelsReport
}

/// Port: the machine's CPU, GPU and memory, read without privileges.
@MainActor
public protocol SystemMetrics: AnyObject {
    /// `agentProcesses` are the live agents' PIDs, whose memory is reported apart.
    func sample(agentProcesses: [Int32]) -> SystemSample
}
