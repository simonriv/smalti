import Foundation
import OSLog
import SmaltiCore

/// Whether Smalti's Claude Code plugin is installed, for ⌘K (spec F5.6). Asking `claude plugin list` takes seconds,
/// so the palette never waits: it reads the last known state, and a check that changes it posts
/// `claudeIntegrationChanged` so an open palette rebuilds its list.
@MainActor
final class ClaudeIntegrationStatus {
    private let integration: any HarnessIntegration
    private(set) var state = IntegrationState.unknown
    private var isChecking = false
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "integration")

    init(integration: any HarnessIntegration) {
        self.integration = integration
    }

    /// Asks again in the background; a check already running is enough.
    func refresh() {
        guard !isChecking else { return }
        isChecking = true
        Task { [weak self, integration] in
            let state = await integration.installState
            self?.finish(with: state)
        }
    }

    private func finish(with newState: IntegrationState) {
        isChecking = false
        logger.notice("claude integration: \(String(describing: newState), privacy: .public)")
        guard newState != state else { return }
        state = newState
        NotificationCenter.default.post(name: .claudeIntegrationChanged, object: self)
    }
}

extension Notification.Name {
    static let claudeIntegrationChanged = Notification.Name("dev.simonriv.smalti.claudeIntegrationChanged")
}
