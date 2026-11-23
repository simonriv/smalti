import Darwin
import Testing

@testable import GhosttyAdapter

@Suite("Foreground process")
struct ForegroundProcessTests {
    @Test func nameOfOwnProcessGroupIsKnown() {
        let group = getpgrp()

        let name = ForegroundProcess.name(ofProcessGroup: group)

        #expect(name?.isEmpty == false)
    }

    @Test(arguments: [pid_t(0), -1])
    func nameOfInvalidPidIsNil(_ pid: pid_t) {
        #expect(ForegroundProcess.name(ofProcessGroup: pid) == nil)
    }
}
