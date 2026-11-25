import Foundation

/// At most one refresh per `interval` (review 2): telemetry batches from several sessions every 5 s would otherwise
/// refresh the open observatory, and reread the transcripts, almost without pause.
public struct RefreshThrottle: Sendable {
    private let interval: TimeInterval
    private var lastRefresh: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// True, and the window restarts, when the last refresh was at least `interval` ago.
    public mutating func shouldRefresh(at now: Date) -> Bool {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < interval { return false }
        lastRefresh = now
        return true
    }
}
