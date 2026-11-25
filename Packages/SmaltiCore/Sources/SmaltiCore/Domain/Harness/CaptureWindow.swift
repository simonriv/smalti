import Foundation

/// Which saved session belongs to a harness that just started in a pane: one created in the pane's directory from
/// a little before the process started, not already claimed by another pane (spec F6, "Captura del ID").
public struct CaptureWindow: Equatable, Sendable {
    /// Clocks of the process table and of the harness's store are not in step.
    public static let margin: TimeInterval = 2

    public let directory: String
    public let processStartedAt: Date
    public let excludedIDs: Set<String>
    /// When other panes of the same harness, in the same directory, started after this one: a session created after
    /// one of them belongs to that pane.
    public let laterStarts: [Date]

    public init(directory: String, processStartedAt: Date, excludedIDs: Set<String>, laterStarts: [Date] = []) {
        self.directory = directory
        self.processStartedAt = processStartedAt
        self.excludedIDs = excludedIDs
        self.laterStarts = laterStarts
    }

    public func admits(_ session: HarnessSession) -> Bool {
        ResolvedPath.same(directory, session.directory)
            && session.createdAt >= processStartedAt.addingTimeInterval(-Self.margin)
            && !excludedIDs.contains(session.id)
            && !laterStarts.contains {
                $0 > processStartedAt && $0.addingTimeInterval(-Self.margin) <= session.createdAt
            }
    }

    /// The first session created after the start: the one this process wrote.
    public func choose(_ sessions: [HarnessSession]) -> String? {
        sessions.filter(admits).min { $0.createdAt < $1.createdAt }?.id
    }
}
