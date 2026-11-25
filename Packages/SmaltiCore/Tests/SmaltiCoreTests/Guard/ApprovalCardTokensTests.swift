import Foundation
import SmaltiCore
import Testing

/// T9: the approval card's tokens come from the theme (preview card surface, "te espera" amber).
@Suite("Approval card tokens")
struct ApprovalCardTokensTests {
    private let theme = Theme.obsidian

    @Test func surfaceIsThePreviewCards() {
        let card = theme.approvalCard

        #expect(card.background == theme.previewCard.background)
        #expect(card.cornerRadius == theme.previewCard.cornerRadius)
        #expect(card.shadowOpacity == theme.previewCard.shadowOpacity)
    }

    @Test func borderAndDotAreTheWaitingAmber() {
        #expect(theme.approvalCard.border == theme.agent.waitingBorder)
        #expect(theme.approvalCard.dot == theme.agent.waiting)
    }

    @Test func commandShowsAtMostEightLines() {
        #expect(theme.approvalCard.maximumCommandLines == 8)
    }

    @Test func appearsWithinTheMotionLimit() {
        #expect(theme.approvalCard.appearDuration <= 0.15)
    }
}

/// T9: UI tests shorten the approval wait with `-SmaltiApprovalTimeoutSeconds`.
@Suite("Approval launch settings")
struct ApprovalLaunchSettingsTests {
    private func settings(_ arguments: [String: String]) -> LaunchSettings {
        LaunchSettings(
            arguments: arguments, home: URL(filePath: "/Users/u"), defaultStateDirectory: URL(filePath: "/tmp/s"))
    }

    @Test func timeoutArgumentIsRead() {
        #expect(settings([LaunchSettings.approvalTimeoutKey: "3"]).approvalTimeout == 3)
    }

    @Test(arguments: [[:], [LaunchSettings.approvalTimeoutKey: "nope"], [LaunchSettings.approvalTimeoutKey: "0"]])
    func missingOrInvalidTimeoutIsTheStandard(arguments: [String: String]) {
        #expect(settings(arguments).approvalTimeout == AgentApprovals.standardTimeout)
    }

    @Test func timeoutKeyIsLaunchArgument() {
        #expect(LaunchSettings.guardArgumentKeys.contains(LaunchSettings.approvalTimeoutKey))
    }

    /// T10: UI tests point ⌘K's secret rules at a temporary project.
    @Test func projectPermissionsRootIsRead() {
        #expect(settings([LaunchSettings.projectPermissionsRootKey: "/tmp/p"]).projectPermissionsRoot == "/tmp/p")
        #expect(settings([:]).projectPermissionsRoot == nil)
        #expect(LaunchSettings.guardArgumentKeys.contains(LaunchSettings.projectPermissionsRootKey))
    }
}
