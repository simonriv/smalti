import Foundation

/// What one session's telemetry says while the app is open: requests, failures, latency and Claude Code's own cost.
public struct SessionTelemetry: Equatable, Sendable {
    public static let recentDurationLimit = 200

    public var since: Date
    public var requests = 0
    public var errors = 0
    /// Failures with an HTTP status, by status; network failures count only in `errors`.
    public var errorsByStatus: [Int: Int] = [:]
    public var costMicroUSD = 0
    var lastEventAt: Date
    private var recentDurations: [Int] = []
    private var sequences: Set<Int> = []

    public init(since: Date) {
        self.since = since
        lastEventAt = since
    }

    /// The median of the latest `recentDurationLimit` request durations (an even count rounds half up); nil before the
    /// first request.
    public var medianMilliseconds: Int? {
        guard !recentDurations.isEmpty else { return nil }
        let sorted = recentDurations.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle] + 1) / 2
    }

    /// Folds one event of this session; a sequence already seen is a repeated delivery and is ignored.
    mutating func apply(_ event: TelemetryEvent) {
        if let sequence = event.sequence, !sequences.insert(sequence).inserted { return }
        since = min(since, event.at)
        lastEventAt = max(lastEventAt, event.at)
        switch event {
        case .apiRequest(let request):
            requests += 1
            costMicroUSD += request.costMicroUSD
            recentDurations.append(request.durationMilliseconds)
            if recentDurations.count > Self.recentDurationLimit { recentDurations.removeFirst() }
        case .apiError(let error):
            errors += 1
            if let status = error.statusCode { errorsByStatus[status, default: 0] += 1 }
        }
    }
}
