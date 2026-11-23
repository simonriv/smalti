import Foundation

/// A quarter of an hour in UTC. Every time zone is offset by a multiple of 15 minutes, so a local midnight is
/// always a boundary and a period can be summed from whole buckets.
public struct QuarterHour: Hashable, Codable, Comparable, Sendable {
    public let start: Date

    public static let length: TimeInterval = 900

    public init(containing date: Date) {
        start = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / Self.length).rounded(.down) * Self.length)
    }

    public static func < (lhs: QuarterHour, rhs: QuarterHour) -> Bool { lhs.start < rhs.start }
}

/// What a session did in one quarter hour.
public struct ActivityBucket: Codable, Equatable, Sendable {
    public var usageByModel: [ModelID: TokenUsage] = [:]
    public var toolCalls = 0
    public var toolErrors = 0
    /// The minute with the most output of the main thread in this quarter, for "pico 4.8k/min · 10:42".
    public var peakMinute: Date?
    public var peakOutput = 0

    public init() {}
}

public enum ToolOutcome: Codable, Equatable, Sendable {
    case succeeded(duration: TimeInterval)
    case failed(exitCode: Int?)
}

public struct RecentTool: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let startedAt: Date
    public let outcome: ToolOutcome
}

/// Everything the observatory keeps about one session, folded from its transcript lines. It is what the index
/// stores, so a later read only folds the new lines.
public struct SessionActivity: Codable, Equatable, Sendable {
    public let sessionID: String
    public private(set) var cwd: String?
    /// The main thread's latest model.
    public private(set) var model: ModelID?
    public private(set) var firstActivity: Date?
    public private(set) var lastActivity: Date?
    public private(set) var buckets: [QuarterHour: ActivityBucket] = [:]
    /// Main-thread output per minute (minute start → tokens), only the hour before the latest turn: the chart.
    public private(set) var outputByMinute: [Date: Int] = [:]
    /// The context the main thread sent with its latest turn.
    public private(set) var contextTokens: Int?
    /// The latest finished main-thread tools, newest first.
    public private(set) var recentTools: [RecentTool] = []
    public private(set) var lastCompaction: Compaction?
    private var countedMessages: Set<String> = []
    private var pendingTools: [String: ToolStart] = [:]

    public static let recentToolLimit = 5
    public static let chartWindow: TimeInterval = 3_600
    private static let minute: TimeInterval = 60

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public func folding(_ records: [TranscriptRecord]) -> SessionActivity {
        records.reduce(into: self) { $0.apply($1) }
    }

    private mutating func apply(_ record: TranscriptRecord) {
        switch record {
        case .assistantTurn(let turn): count(turn)
        case .toolStarted(let start): begin(start)
        case .toolFinished(let finish): end(finish)
        case .compacted(let compaction):
            touch(compaction.at)
            if lastCompaction.map({ $0.at <= compaction.at }) ?? true { lastCompaction = compaction }
        case .sessionInfo(_, let path, _):
            if cwd == nil, !path.isEmpty { cwd = path }
        }
    }

    private mutating func count(_ turn: AssistantTurn) {
        guard countedMessages.insert(turn.messageID).inserted else { return }
        touch(turn.at)
        let quarter = QuarterHour(containing: turn.at)
        buckets[quarter, default: ActivityBucket()].usageByModel[turn.model, default: .zero] =
            (buckets[quarter]?.usageByModel[turn.model] ?? .zero) + turn.usage
        guard !turn.isSubagent, turn.model != .synthetic, turn.usage != .zero else { return }
        model = turn.model
        contextTokens = turn.usage.inputTotal
        chart(turn, in: quarter)
    }

    private mutating func chart(_ turn: AssistantTurn, in quarter: QuarterHour) {
        let minute = Date(
            timeIntervalSince1970: (turn.at.timeIntervalSince1970 / Self.minute).rounded(.down) * Self.minute)
        let minuteOutput = outputByMinute[minute, default: 0] + turn.usage.output
        outputByMinute[minute] = minuteOutput
        let cutoff = (outputByMinute.keys.max() ?? minute).addingTimeInterval(-Self.chartWindow)
        outputByMinute = outputByMinute.filter { $0.key > cutoff }
        if minuteOutput > buckets[quarter, default: ActivityBucket()].peakOutput {
            buckets[quarter]?.peakOutput = minuteOutput
            buckets[quarter]?.peakMinute = minute
        }
    }

    private mutating func begin(_ start: ToolStart) {
        touch(start.at)
        pendingTools[start.id] = start
    }

    private mutating func end(_ finish: ToolFinish) {
        guard let start = pendingTools.removeValue(forKey: finish.id) else { return }
        touch(finish.at)
        let quarter = QuarterHour(containing: finish.at)
        buckets[quarter, default: ActivityBucket()].toolCalls += 1
        if finish.isError { buckets[quarter]?.toolErrors += 1 }
        let outcome: ToolOutcome =
            finish.isError
            ? .failed(exitCode: finish.exitCode) : .succeeded(duration: finish.at.timeIntervalSince(start.at))
        let summary = ToolSummary.text(name: start.name, input: start.input, diff: finish.diff)
        let tool = RecentTool(id: start.id, name: start.name, summary: summary, startedAt: start.at, outcome: outcome)
        recentTools = Array(([tool] + recentTools).prefix(Self.recentToolLimit))
    }

    private mutating func touch(_ date: Date) {
        firstActivity = min(firstActivity ?? date, date)
        lastActivity = max(lastActivity ?? date, date)
    }
}
