import SmaltiCore
import Testing

@Suite("StatusSlot")
struct StatusSlotTests {
    private let empty = StatusSlot<String>()

    @Test func emptySlotShowsNothing() {
        #expect(empty.showing == nil)
    }

    @Test func persistentMessageShows() {
        let slot = empty.withPersistent("config.toml:3 · keys")

        #expect(slot.showing == "config.toml:3 · keys")
    }

    @Test func transientShowsOverPersistent() {
        let slot = empty.withPersistent("error").withTransient("no cabe")

        #expect(slot.showing == "no cabe")
    }

    @Test func clearingTheTransientRevealsThePersistentAgain() {
        let slot = empty.withPersistent("error").withTransient("no cabe")

        let cleared = slot.clearingTransient("no cabe")

        #expect(cleared.showing == "error")
    }

    @Test func clearingAnOlderTransientKeepsTheNewerOne() {
        let slot = empty.withTransient("first").withTransient("second")

        let cleared = slot.clearingTransient("first")

        #expect(cleared.showing == "second")
    }

    @Test func clearingWithNoTransientChangesNothing() {
        let slot = empty.withPersistent("error")

        #expect(slot.clearingTransient("error") == slot)
    }

    @Test func newPersistentReplacesTheTransientSoTheNewestMessageShows() {
        let slot = empty.withTransient("no cabe")

        let updated = slot.withPersistent("error")

        #expect(updated.showing == "error")
        #expect(updated.transient == nil)
    }

    @Test func clearingThePersistentLeavesNothing() {
        let slot = empty.withPersistent("error").withTransient("no cabe")

        let cleared = slot.withPersistent(nil)

        #expect(cleared.showing == nil)
    }
}
