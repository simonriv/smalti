import Foundation
import OSLog
import SmaltiCore
import UserNotifications

/// macOS notifications. Permission is asked the first time there is something to notify; a click on a notification
/// calls `onActivate` with its pane. A denied permission is not an error: the panes keep showing the state, and
/// `onDenied` runs once so the app can say so.
@MainActor
public final class UserNotificationsNotifier: NSObject, Notifier {
    nonisolated private static let paneKey = "pane"
    private let center: UNUserNotificationCenter
    private let onActivate: @MainActor (PaneID) -> Void
    private let onDenied: @MainActor () -> Void
    private var hasAsked = false
    private var isAllowed = false
    private var hasReportedDenial = false
    private let logger = Logger(subsystem: "dev.simonriv.smalti", category: "notifications")

    public init(onActivate: @escaping @MainActor (PaneID) -> Void, onDenied: @escaping @MainActor () -> Void) {
        center = .current()
        self.onActivate = onActivate
        self.onDenied = onDenied
        super.init()
        center.delegate = self
    }

    public func notify(_ notice: AttentionNotice) {
        Task { [weak self] in await self?.deliver(notice) }
    }

    private func deliver(_ notice: AttentionNotice) async {
        guard await allowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.userInfo = [Self.paneKey: notice.pane.description]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logger.error("could not post a notification: \(String(describing: error), privacy: .public)")
        }
    }

    private func allowed() async -> Bool {
        if !hasAsked {
            hasAsked = true
            isAllowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        if !isAllowed, !hasReportedDenial {
            hasReportedDenial = true
            onDenied()
        }
        return isAllowed
    }

    fileprivate func activate(_ userInfo: [AnyHashable: Any]) {
        guard let text = userInfo[Self.paneKey] as? String, let id = UUID(uuidString: text) else { return }
        onActivate(PaneID(rawValue: id))
    }
}

extension UserNotificationsNotifier: UNUserNotificationCenterDelegate {
    /// Shown even while Smalti is in front (the policy already decided it should be).
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        // Only the pane id string crosses to the main actor.
        let pane = userInfo[Self.paneKey] as? String
        await MainActor.run { self.activate(pane.map { [Self.paneKey: $0] } ?? [:]) }
    }
}
