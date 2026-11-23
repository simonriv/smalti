import OSLog
import SmaltiCore

/// Logs notices until macOS notifications are wired (T22); kept as the fallback when they are unavailable.
@MainActor
final class LogNotifier: Notifier {
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "attention")

    func notify(_ notice: AttentionNotice) {
        logger.info("\(notice.title, privacy: .public): \(notice.body, privacy: .public)")
    }
}
