/// Why the welcome card's mark could not be written.
public enum WelcomeRecordError: Error, Equatable, Sendable {
    case unwritable(path: String, reason: String)
}

/// Port (F7.7): whether the welcome card was already seen (closed with ↩ or esc), kept with the app's state.
public protocol WelcomeRecord: Sendable {
    var isDone: Bool { get async }
    func markDone() async throws(WelcomeRecordError)
}

/// Decides at launch whether the welcome card opens (spec F7.7): only on a fresh install, never for someone who
/// already used Smalti (a saved session), whom it marks as done right away.
@MainActor
public struct ShowWelcome {
    private let record: any WelcomeRecord

    public init(record: any WelcomeRecord) {
        self.record = record
    }

    public func shouldShowAtLaunch(hasSavedSession: Bool) async -> Bool {
        guard await !record.isDone else { return false }
        guard !hasSavedSession else {
            // Best effort: if the mark cannot be written, the saved session keeps hiding the card next time too.
            try? await record.markDone()
            return false
        }
        return true
    }
}
