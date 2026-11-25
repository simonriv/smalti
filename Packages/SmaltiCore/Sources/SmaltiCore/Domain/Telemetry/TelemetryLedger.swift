import Foundation

/// Every session's telemetry received since the app opened, bounded to `sessionLimit` sessions: past it, the session
/// quiet for longest is dropped.
public struct TelemetryLedger: Equatable, Sendable {
    public static let sessionLimit = 200

    private var sessions: [String: SessionTelemetry] = [:]

    public init() {}

    public var isEmpty: Bool { sessions.isEmpty }

    public func telemetry(of sessionID: String) -> SessionTelemetry? { sessions[sessionID] }

    public mutating func record(_ events: [TelemetryEvent]) {
        for event in events {
            sessions[event.sessionID, default: SessionTelemetry(since: event.at)].apply(event)
            if sessions.count > Self.sessionLimit { dropQuietest() }
        }
    }

    private mutating func dropQuietest() {
        guard let quietest = sessions.min(by: { $0.value.lastEventAt < $1.value.lastEventAt })?.key else { return }
        sessions[quietest] = nil
    }
}
