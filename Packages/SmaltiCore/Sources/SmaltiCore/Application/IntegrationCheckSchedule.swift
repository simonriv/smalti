import Foundation

/// When to ask a harness again whether Smalti's integration is installed (F5.6). Asking costs seconds of CPU
/// (`claude plugin list`), so an unforced request (opening ⌘K) waits `minimumInterval` after the last answer;
/// launch, install and uninstall force one. Only one check runs at a time: a forced request made meanwhile runs
/// right after it, so its answer is never one taken before an install.
public struct IntegrationCheckSchedule: Sendable {
    public static let standardInterval: TimeInterval = 30

    private let minimumInterval: TimeInterval
    private var isChecking = false
    private var isRecheckPending = false
    private var lastAnswer: Date?

    public init(minimumInterval: TimeInterval = standardInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Whether to start a check now.
    public mutating func shouldStart(forced: Bool, now: Date) -> Bool {
        if isChecking {
            isRecheckPending = isRecheckPending || forced
            return false
        }
        if !forced, let lastAnswer, now.timeIntervalSince(lastAnswer) < minimumInterval { return false }
        isChecking = true
        return true
    }

    /// The running check answered; `true` means start another one at once.
    public mutating func finished(at now: Date) -> Bool {
        lastAnswer = now
        guard isRecheckPending else {
            isChecking = false
            return false
        }
        isRecheckPending = false
        return true
    }
}
