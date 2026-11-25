import Foundation

/// A Claude process alive on this machine, from `~/.claude/sessions/<pid>.json`.
public struct RunningAgent: Equatable, Sendable {
    public let pid: Int32
    public let sessionID: String
    public let cwd: String
    public let status: String
    public let startedAt: Date

    public init(pid: Int32, sessionID: String, cwd: String, status: String, startedAt: Date) {
        self.pid = pid
        self.sessionID = sessionID
        self.cwd = cwd
        self.status = status
        self.startedAt = startedAt
    }
}

public struct LocalModel: Equatable, Sendable {
    public let name: String
    public let quantization: String?
    public let bytes: UInt64
    public let vramBytes: UInt64?
    public let contextLength: Int?
    /// When it was pulled: Ollama keeps no last-use date ("descargado hace 2 días").
    public let downloadedAt: Date?

    public init(
        name: String, quantization: String?, bytes: UInt64, vramBytes: UInt64?, contextLength: Int?,
        downloadedAt: Date?
    ) {
        self.name = name
        self.quantization = quantization
        self.bytes = bytes
        self.vramBytes = vramBytes
        self.contextLength = contextLength
        self.downloadedAt = downloadedAt
    }
}

public enum LocalModelsReport: Equatable, Sendable {
    case unavailable
    case available(loaded: [LocalModel], onDisk: [LocalModel])
}

/// A reading that may not be possible without privileges: shown as "no disponible", never as 0.
public enum Reading<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    case unavailable

    public var value: Value? {
        guard case .value(let value) = self else { return nil }
        return value
    }
}

public enum MemoryPressure: String, Equatable, Sendable {
    case normal, media, alta
}

public struct SystemSample: Equatable, Sendable {
    public var cpu: Reading<Double>
    public var gpu: Reading<Double>
    public var memoryUsed: Reading<UInt64>
    public var memoryTotal: UInt64
    public var agentsMemory: Reading<UInt64>
    public var pressure: Reading<MemoryPressure>
    public var machineName: String

    public init(
        cpu: Reading<Double>, gpu: Reading<Double>, memoryUsed: Reading<UInt64>, memoryTotal: UInt64,
        agentsMemory: Reading<UInt64>, pressure: Reading<MemoryPressure>, machineName: String
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.agentsMemory = agentsMemory
        self.pressure = pressure
        self.machineName = machineName
    }
}

/// What went wrong reading the transcripts so far: shown in the log, never silently swallowed.
public struct TranscriptHealth: Equatable, Sendable {
    public var skippedLines = 0
    public var readFailures = 0
    public var indexWriteFailures = 0

    public init(skippedLines: Int = 0, readFailures: Int = 0, indexWriteFailures: Int = 0) {
        self.skippedLines = skippedLines
        self.readFailures = readFailures
        self.indexWriteFailures = indexWriteFailures
    }

    public static let healthy = TranscriptHealth()
}

/// The transcripts' sessions and the date since which the index holds every file.
public struct TranscriptActivity: Equatable, Sendable {
    public let sessions: [SessionActivity]
    public let indexedSince: Date
    public let health: TranscriptHealth

    public init(sessions: [SessionActivity], indexedSince: Date, health: TranscriptHealth = .healthy) {
        self.sessions = sessions
        self.indexedSince = indexedSince
        self.health = health
    }
}

/// A Smalti pane with an agent: its hooks are the freshest word on the session's state.
public struct PaneAgent: Equatable, Sendable {
    public let pane: PaneID
    /// `<workspace>/<último directorio>`, as in F2's notifications.
    public let label: String
    public let session: AgentSession

    public init(pane: PaneID, label: String, session: AgentSession) {
        self.pane = pane
        self.label = label
        self.session = session
    }
}

extension PaneAgent {
    /// Every pane of every workspace with an agent, labelled like F2's notifications.
    public static func all(in set: WorkspaceSet) -> [PaneAgent] {
        set.workspaces.flatMap { workspace in
            workspace.panes.compactMap { pane in
                pane.agent.map {
                    PaneAgent(
                        pane: pane.id, label: "\(workspace.name)/\(pane.workingDirectory.lastComponent)", session: $0)
                }
            }
        }
    }
}

/// Everything one refresh gathered; the report, the status bar and the pane headers are drawn from it.
public struct ObservatorySnapshot: Equatable, Sendable {
    public let activity: TranscriptActivity
    public let running: [RunningAgent]
    public let panes: [PaneAgent]
    public let localModels: LocalModelsReport
    public let system: SystemSample
    public let cpuHistory: [Double]
    public let gpuHistory: [Double]
    public let catalog: ModelCatalog
    public let now: Date
    /// The user's home, to label sessions outside Smalti (`~`, `termotty`, `solen/api`).
    public let home: String
    /// Why the transcripts could not be read this time; the previous sessions are kept.
    public let lastError: String?
    /// F6: other harnesses' sessions (OpenCode), as their own stores count them.
    public private(set) var usage: [UsageRow] = []

    public init(
        activity: TranscriptActivity, running: [RunningAgent], panes: [PaneAgent], localModels: LocalModelsReport,
        system: SystemSample, cpuHistory: [Double], gpuHistory: [Double], catalog: ModelCatalog, now: Date,
        home: String, lastError: String?
    ) {
        self.activity = activity
        self.running = running
        self.panes = panes
        self.localModels = localModels
        self.system = system
        self.cpuHistory = cpuHistory
        self.gpuHistory = gpuHistory
        self.catalog = catalog
        self.now = now
        self.home = home
        self.lastError = lastError
    }

    public func adding(usage rows: [UsageRow]) -> ObservatorySnapshot {
        var copy = self
        copy.usage = rows
        return copy
    }
}
