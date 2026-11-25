import Foundation

/// What one session's telemetry says while the app is open: requests, failures, latency and Claude Code's own cost.
public struct SessionTelemetry: Equatable, Sendable {
    public static let recentDurationLimit = 200
    /// How many recent deliveries a session remembers to recognize a repeat; older ones are forgotten (bounded memory).
    public static let deliveryWindow = 1000

    public var since: Date
    public var requests = 0
    public var errors = 0
    /// Failures with an HTTP status, by status; network failures count only in `errors`.
    public var errorsByStatus: [Int: Int] = [:]
    public var costMicroUSD = 0
    var lastEventAt: Date
    private var recentDurations: [Int] = []
    /// Deliveries seen, by sequence and time: a relaunched Claude on the same session starts its sequence again.
    private var deliveries: Set<Delivery> = []
    private var deliveryOrder: [Delivery] = []

    private struct Delivery: Hashable {
        let sequence: Int
        let at: Date
    }

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
        guard sorted.count % 2 == 0 else { return sorted[middle] }
        let (low, high) = (sorted[middle - 1], sorted[middle])
        // (low + high + 1) / 2 without overflowing near Int.max.
        return low / 2 + high / 2 + (low % 2 + high % 2 + 1) / 2
    }

    /// False for a delivery already seen; remembers a new one, forgetting the oldest past `deliveryWindow`.
    private mutating func remember(_ delivery: Delivery) -> Bool {
        guard deliveries.insert(delivery).inserted else { return false }
        deliveryOrder.append(delivery)
        if deliveryOrder.count > Self.deliveryWindow { deliveries.remove(deliveryOrder.removeFirst()) }
        return true
    }

    private static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? (rhs > 0 ? Int.max : Int.min) : sum
    }

    /// Folds one event of this session; a sequence already seen is a repeated delivery and is ignored.
    mutating func apply(_ event: TelemetryEvent) {
        if let sequence = event.sequence, !remember(Delivery(sequence: sequence, at: event.at)) { return }
        since = min(since, event.at)
        lastEventAt = max(lastEventAt, event.at)
        switch event {
        case .apiRequest(let request):
            requests += 1
            costMicroUSD = Self.saturatingSum(costMicroUSD, request.costMicroUSD)
            recentDurations.append(request.durationMilliseconds)
            if recentDurations.count > Self.recentDurationLimit { recentDurations.removeFirst() }
        case .apiError(let error):
            errors += 1
            if let status = error.statusCode { errorsByStatus[status, default: 0] += 1 }
        }
    }
}
