import Darwin
import Foundation
import Testing

@testable import GhosttyAdapter

@Suite("Process arguments")
struct ProcessArgumentsTests {
    @Test func argumentsOfOwnProcess() {
        let arguments = ProcessArguments.of(pid: getpid())

        #expect(
            arguments?.first.map { CommandLine.arguments.first?.hasSuffix(($0 as NSString).lastPathComponent) == true }
                == true)
        #expect(arguments?.count == CommandLine.arguments.count)
    }

    @Test func argumentsOfMissingProcessIsNil() {
        #expect(ProcessArguments.of(pid: 999_999) == nil)
    }

    @Test func trackerAttachesTheCommandLineWhenTheNameChanges() {
        var tracker = ProcessNameTracker()

        let event = tracker.observe("node", commandLine: { ["pnpm", "dev"] })

        #expect(event == .foregroundProcessChanged(.init(name: "node", commandLine: ["pnpm", "dev"])))
    }

    @Test func trackerDoesNotReadTheCommandLineWithoutAChange() {
        var tracker = ProcessNameTracker()
        _ = tracker.observe("node", commandLine: { ["pnpm"] })
        var reads = 0

        _ = tracker.observe(
            "node",
            commandLine: {
                reads += 1
                return nil
            })

        #expect(reads == 0)
    }
}
