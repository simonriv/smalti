import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// F7.6: checking for updates and turning the automatic check on or off.
@MainActor
@Suite("AppUpdates")
struct AppUpdatesTests {
    private let updates = FakeAppUpdates(isAutomatic: true)

    @Test func checkAsksTheUpdaterOnce() {
        CheckForUpdates(updates: updates).execute()

        #expect(updates.checks == 1)
    }

    @Test func toggleTurnsAutomaticOff() {
        let message = SetAutomaticUpdates(updates: updates, texts: .spanish).toggle()

        #expect(!updates.isAutomatic)
        #expect(message == "Actualizaciones automáticas desactivadas")
    }

    @Test func toggleTurnsAutomaticOn() {
        let updates = FakeAppUpdates(isAutomatic: false)

        let message = SetAutomaticUpdates(updates: updates, texts: .spanish).toggle()

        #expect(updates.isAutomatic)
        #expect(message == "Actualizaciones automáticas activadas")
    }

    @Test func availabilityReflectsTheUpdater() {
        #expect(UpdatesAvailability(updates) == .available(isAutomatic: true))
        #expect(UpdatesAvailability(nil) == .unavailable)
    }
}
