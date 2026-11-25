import Foundation

/// The sessions of every harness together, newest first; the failures stay apart so one broken harness does not
/// hide the others (spec F6).
public struct SessionListing: Equatable, Sendable {
    public let sessions: [HarnessSession]
    public let failures: [HarnessID: HarnessError]

    public init(sessions: [HarnessSession], failures: [HarnessID: HarnessError]) {
        self.sessions = sessions
        self.failures = failures
    }
}

public enum SessionCatalog {
    public static func merge(_ lists: [Result<[HarnessSession], HarnessError>], query: SessionQuery)
        -> SessionListing
    {
        var sessions: [HarnessSession] = []
        var failures: [HarnessID: HarnessError] = [:]
        for list in lists {
            switch list {
            case .success(let found): sessions += found.filter { ShellWord.isSafeID($0.id) && query.matches($0) }
            case .failure(let error): failures[error.harness] = error
            }
        }
        let newest = sessions.sorted { $0.updatedAt > $1.updatedAt }
        return SessionListing(sessions: Array(newest.prefix(query.limit)), failures: failures)
    }
}
