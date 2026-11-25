import Foundation

public struct OutputPeak: Equatable, Sendable {
    public let output: Int
    public let at: Date

    public init(output: Int, at: Date) {
        self.output = output
        self.at = at
    }
}

/// What the observatory screen shows for one period and one selected session.
public struct ObservatoryReport: Equatable, Sendable {
    public struct Summary: Equatable, Sendable {
        public let active: Int
        public let working: Int
        public let waiting: Int
        public let failed: Int
        public let input: Int
        /// Percent of the input read from the cache; nil without input.
        public let cacheShare: Int?
        public let output: Int
        public let peak: OutputPeak?
        public let cost: CostEstimate
        /// False while the index still reads files older than the period's start ("leyendo transcripts…").
        public let isComplete: Bool

        public init(
            active: Int, working: Int, waiting: Int, failed: Int, input: Int, cacheShare: Int?, output: Int,
            peak: OutputPeak?, cost: CostEstimate, isComplete: Bool
        ) {
            self.active = active
            self.working = working
            self.waiting = waiting
            self.failed = failed
            self.input = input
            self.cacheShare = cacheShare
            self.output = output
            self.peak = peak
            self.cost = cost
            self.isComplete = isComplete
        }
    }

    public struct Row: Equatable, Sendable {
        public let id: String
        public let state: AgentStateKind
        public let label: String
        public let agentModel: String
        public let lifetime: String
        public let input: String
        public let output: String
        public let context: ContextLoad
        public let errorRate: Int
        public let isErrorRateHigh: Bool
        public let pid: String
        public let pane: PaneID?
    }

    public struct Detail: Equatable, Sendable {
        public let sessionID: String
        public let title: String
        public let tools: [RecentTool]
        /// Output per minute for the last hour, oldest first, ending with the current minute.
        public let outputPerMinute: [Int]
        public let peak: OutputPeak?
        public let compaction: String
    }

    public let summary: Summary
    public let rows: [Row]
    public let detail: Detail?

    /// From 5 % of failed tools the rate turns red (the board shows 2 % plain and 9 % red).
    public static let highErrorRate = 5

    /// What the screen asks for: a period, the selected session and the calendar that knows the time zone.
    public struct Request: Sendable {
        public let period: ObservatoryPeriod
        public let selection: String?
        public let calendar: Calendar
        /// F6: which harnesses the table and the summary count.
        public let filter: ObservatoryFilter

        public init(
            period: ObservatoryPeriod, selection: String?, calendar: Calendar, filter: ObservatoryFilter = .all
        ) {
            self.period = period
            self.selection = selection
            self.calendar = calendar
            self.filter = filter
        }
    }

    public static func make(_ snapshot: ObservatorySnapshot, for request: Request) -> ObservatoryReport {
        let start = request.period.start(now: snapshot.now, calendar: request.calendar)
        let window = PeriodWindow(start: start, end: snapshot.now)
        let sessions = request.filter.includesClaude ? ordered(ObservedSession.merge(snapshot), in: window) : []
        let others = snapshot.usage.filter { $0.updatedAt >= start && request.filter.includes($0) }
            .sorted { newerFirst($0.updatedAt, $1.updatedAt, $0.sessionID, $1.sessionID) }
        let rows =
            sessions.map { row(for: $0, in: window, snapshot: snapshot) } + others.map { row(for: $0, snapshot) }
        return ObservatoryReport(
            summary: summary(sessions, others: others, in: window, snapshot: snapshot),
            rows: rows,
            detail: detail(selecting: request.selection, sessions: sessions, others: others, snapshot: snapshot))
    }

    /// The selected row's detail; a selection no longer listed falls back to the first row.
    private static func detail(
        selecting selection: String?, sessions: [ObservedSession], others: [UsageRow], snapshot: ObservatorySnapshot
    ) -> Detail? {
        if let session = sessions.first(where: { $0.id == selection }) {
            return detail(for: session, snapshot: snapshot)
        }
        if let usage = others.first(where: { $0.sessionID == selection }) { return detail(for: usage, snapshot) }
        return sessions.first.map { detail(for: $0, snapshot: snapshot) }
            ?? others.first.map { detail(for: $0, snapshot) }
    }

    private static let noFigure = "—"

    /// OpenCode counts cache reads inside its input; Claude's figures keep them apart.
    private static func tokenUsage(of usage: UsageRow) -> TokenUsage {
        TokenUsage(
            input: usage.input - usage.cacheRead, output: usage.output, cacheRead: usage.cacheRead, cacheWrite5m: 0,
            cacheWrite1h: 0)
    }

    /// F6: an OpenCode session, from its database's totals; no live state is known for it ("—" en vida).
    private static func row(for usage: UsageRow, _ snapshot: ObservatorySnapshot) -> Row {
        let model = usage.model.map { "\(usage.harness.displayName) · \($0)\(usage.isLocal ? " local" : "")" }
        return Row(
            id: usage.sessionID, state: .stopped,
            label: ObservedSession.label(cwd: usage.directory, home: snapshot.home),
            agentModel: model ?? usage.harness.displayName,
            lifetime: noFigure,
            input: ObservatoryFormat.count(usage.input), output: ObservatoryFormat.count(usage.output),
            context: .unavailable, errorRate: 0, isErrorRateHigh: false, pid: "—", pane: nil)
    }

    private static func detail(for usage: UsageRow, _ snapshot: ObservatorySnapshot) -> Detail {
        Detail(
            sessionID: usage.sessionID,
            title: "Actividad · \(ObservedSession.label(cwd: usage.directory, home: snapshot.home))", tools: [],
            outputPerMinute: Array(repeating: 0, count: chartMinutes), peak: nil, compaction: "Sin compactaciones")
    }

    private static func ordered(_ sessions: [ObservedSession], in window: PeriodWindow) -> [ObservedSession] {
        let live = sessions.filter(\.isLive).sorted { newerFirst($0.startedAt, $1.startedAt, $0.id, $1.id) }
        let stopped = sessions.filter { !$0.isLive && window.hasActivity($0.activity) }
            .sorted { newerFirst($0.activity.lastActivity, $1.activity.lastActivity, $0.id, $1.id) }
        return live + stopped
    }

    /// Newest first; ties by id, so rows never swap places between refreshes.
    private static func newerFirst(_ lhs: Date?, _ rhs: Date?, _ lhsID: String, _ rhsID: String) -> Bool {
        let left = lhs ?? .distantPast
        let right = rhs ?? .distantPast
        return left == right ? lhsID < rhsID : left > right
    }

    private static func summary(
        _ sessions: [ObservedSession], others: [UsageRow], in window: PeriodWindow, snapshot: ObservatorySnapshot
    ) -> Summary {
        let live = sessions.filter(\.isLive)
        let usage = sessions.map { window.usage(of: $0.activity) }.reduce(into: [ModelID: TokenUsage]()) {
            total, next in
            total.merge(next, uniquingKeysWith: +)
        }
        let tokens = usage.values.reduce(.zero, +) + others.reduce(.zero) { $0 + tokenUsage(of: $1) }
        return Summary(
            active: live.count, working: live.filter { $0.state == .working }.count,
            waiting: live.filter { $0.state == .waiting }.count, failed: live.filter { $0.state == .failed }.count,
            input: tokens.inputTotal, cacheShare: tokens.cacheShare.map { Int(($0 * 100).rounded()) },
            output: tokens.output,
            peak: sessions.compactMap { window.peak(of: $0.activity) }.max { $0.output < $1.output },
            cost: CostEstimate.of(usage, catalog: snapshot.catalog),
            isComplete: snapshot.activity.indexedSince <= window.start)
    }

    private static func row(for session: ObservedSession, in window: PeriodWindow, snapshot: ObservatorySnapshot) -> Row
    {
        let tokens = window.usage(of: session.activity).values.reduce(.zero, +)
        let tools = window.tools(of: session.activity)
        let errorRate = tools.calls == 0 ? 0 : Int((Double(tools.errors) * 100 / Double(tools.calls)).rounded())
        let model = session.activity.model.map { "Claude Code · \($0.family)" } ?? "Claude Code"
        return Row(
            id: session.id, state: session.state, label: session.label, agentModel: model,
            lifetime: lifetime(of: session, now: snapshot.now),
            input: ObservatoryFormat.count(tokens.inputTotal), output: ObservatoryFormat.count(tokens.output),
            context: session.isLive
                ? ContextLoad.of(
                    contextTokens: session.activity.contextTokens, model: session.activity.model,
                    catalog: snapshot.catalog) : .unavailable,
            errorRate: errorRate, isErrorRateHigh: errorRate >= highErrorRate,
            pid: session.pid.map(String.init) ?? "—", pane: session.pane)
    }

    private static func lifetime(of session: ObservedSession, now: Date) -> String {
        if session.isLive { return ObservatoryFormat.lifetime(now.timeIntervalSince(session.startedAt ?? now)) }
        return ObservatoryFormat.agoCompact(now.timeIntervalSince(session.activity.lastActivity ?? now))
    }

    private static let minute: TimeInterval = 60
    private static let chartMinutes = 60

    private static func detail(for session: ObservedSession, snapshot: ObservatorySnapshot) -> Detail {
        let nowMinute = (snapshot.now.timeIntervalSince1970 / minute).rounded(.down) * minute
        let minutes = (0..<chartMinutes).map {
            Date(timeIntervalSince1970: nowMinute - Double(chartMinutes - 1 - $0) * minute)
        }
        let series = minutes.map { session.activity.outputByMinute[$0] ?? 0 }
        let peak = zip(series, minutes).max { $0.0 < $1.0 }.flatMap {
            $0.0 > 0 ? OutputPeak(output: $0.0, at: $0.1) : nil
        }
        return Detail(
            sessionID: session.id, title: "Actividad · \(session.label)", tools: session.activity.recentTools,
            outputPerMinute: series, peak: peak, compaction: compactionText(session.activity, snapshot: snapshot))
    }

    private static func compactionText(_ activity: SessionActivity, snapshot: ObservatorySnapshot) -> String {
        guard let compaction = activity.lastCompaction else { return "Sin compactaciones" }
        let ago = ObservatoryFormat.ago(snapshot.now.timeIntervalSince(compaction.at))
        guard let model = activity.model, let window = snapshot.catalog.pricing(for: model)?.contextWindow, window > 0
        else { return "Compactación \(ago)" }
        let freed = Int((Double(compaction.preTokens - compaction.postTokens) * 100 / Double(window)).rounded())
        return "Compactación \(ago) · liberó \(freed)% del contexto"
    }
}

/// The quarter hours from a period's start until now.
struct PeriodWindow {
    let start: Date
    let end: Date

    private func buckets(of activity: SessionActivity) -> [ActivityBucket] {
        activity.buckets.filter { $0.key.start >= start && $0.key.start <= end }.map(\.value)
    }

    func hasActivity(_ activity: SessionActivity) -> Bool { !buckets(of: activity).isEmpty }

    func usage(of activity: SessionActivity) -> [ModelID: TokenUsage] {
        buckets(of: activity).reduce(into: [:]) { total, bucket in total.merge(bucket.usageByModel, uniquingKeysWith: +)
        }
    }

    func tools(of activity: SessionActivity) -> (calls: Int, errors: Int) {
        buckets(of: activity).reduce((0, 0)) { ($0.0 + $1.toolCalls, $0.1 + $1.toolErrors) }
    }

    func peak(of activity: SessionActivity) -> OutputPeak? {
        buckets(of: activity).compactMap { bucket in
            bucket.peakMinute.map { OutputPeak(output: bucket.peakOutput, at: $0) }
        }
        .max { $0.output < $1.output }
    }
}
