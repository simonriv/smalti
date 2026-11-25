import Foundation
import OSLog
import SmaltiCore

/// Whether Smalti's Claude Code plugin is installed, for ⌘K (spec F5.6). Asking `claude plugin list` takes seconds,
/// so the palette never waits: it reads the last known state, and a check that changes it posts
/// `claudeIntegrationChanged` so an open palette rebuilds its list. `IntegrationCheckSchedule` decides when to ask.
@MainActor
final class ClaudeIntegrationStatus {
    private let integration: any HarnessIntegration
    private(set) var state = IntegrationState.unknown
    private var schedule: IntegrationCheckSchedule
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "integration")

    /// UI tests shorten the wait between checks with `-SmaltiIntegrationRecheckSeconds`.
    init(integration: any HarnessIntegration) {
        self.integration = integration
        // A launch argument arrives as text: `double(forKey:)` converts it, `object(forKey:) as? Double` would not.
        let key = "SmaltiIntegrationRecheckSeconds"
        let defaults = UserDefaults.standard
        let interval =
            defaults.object(forKey: key) == nil
            ? IntegrationCheckSchedule.standardInterval : defaults.double(forKey: key)
        schedule = IntegrationCheckSchedule(minimumInterval: interval)
    }

    /// Asks again in the background: `forced` at launch and after an install or uninstall; opening ⌘K is not.
    func refresh(forced: Bool) {
        guard schedule.shouldStart(forced: forced, now: Date()) else { return }
        check()
    }

    /// An install or uninstall started: until it answers, ⌘K offers neither action, so it cannot be run twice.
    func changeStarted() {
        guard state != .unknown else { return }
        state = .unknown
        NotificationCenter.default.post(name: .claudeIntegrationChanged, object: self)
    }

    private func check() {
        Task { [weak self, integration] in
            let state = await integration.installState
            self?.finish(with: state)
        }
    }

    private func finish(with newState: IntegrationState) {
        logger.notice("claude integration: \(String(describing: newState), privacy: .public)")
        if newState != state {
            state = newState
            NotificationCenter.default.post(name: .claudeIntegrationChanged, object: self)
        }
        if schedule.finished(at: Date()) { check() }
    }
}

extension Notification.Name {
    static let claudeIntegrationChanged = Notification.Name("dev.simonriv.smalti.claudeIntegrationChanged")
}
