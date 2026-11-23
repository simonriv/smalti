import Testing

@testable import UserNotificationsAdapter

@MainActor
@Suite("Notification authorization gate")
struct AuthorizationGateTests {
    @Test func noticesWhileThePromptIsOpenWaitForTheAnswer() async {
        var denials = 0
        var requests = 0
        let gate = AuthorizationGate(
            current: { nil },
            request: {
                requests += 1
                try? await Task.sleep(for: .milliseconds(100))
                return true
            },
            onDenied: { denials += 1 })

        async let first = gate.isAllowed()
        async let second = gate.isAllowed()
        let answers = await [first, second]

        #expect(answers == [true, true])
        #expect(requests == 1)
        #expect(denials == 0)
    }

    @Test func aDenialIsReportedOnce() async {
        var denials = 0
        let gate = AuthorizationGate(current: { false }, request: { false }, onDenied: { denials += 1 })

        _ = await gate.isAllowed()
        _ = await gate.isAllowed()

        #expect(denials == 1)
    }

    @Test func permissionGrantedLaterInSettingsIsHonoured() async {
        var granted = false
        let gate = AuthorizationGate(current: { granted }, request: { false }, onDenied: {})

        #expect(await !gate.isAllowed())
        granted = true

        #expect(await gate.isAllowed())
    }
}
