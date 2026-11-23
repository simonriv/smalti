import Foundation
import SmaltiCore
import Testing

@Suite("InputProtocol")
struct InputProtocolTests {
    private let pane = PaneID(rawValue: UUID(uuidString: "6F2B4E1C-0A3D-4C5E-9F11-2233445566AA") ?? UUID())

    @Test func decodesHello() throws {
        let message = try InputProtocol.decode("hello\t6F2B4E1C-0A3D-4C5E-9F11-2233445566AA").message

        #expect(message == .hello(pane))
    }

    @Test func decodesLine() throws {
        let message = try InputProtocol.decode("line\t7\t/repo\t3\tgit ch").message

        #expect(message == .line(seq: 7, InputLine(text: "git ch", cursor: 3)))
    }

    @Test func decodesExecAndDone() throws {
        #expect(try InputProtocol.decode("exec\t8\t/repo\tswift test").message == .exec(seq: 8, command: "swift test"))
        #expect(try InputProtocol.decode("done\t9\t127").message == .done(seq: 9, exit: 127))
    }

    @Test func decodesCompleteHistoryAndBye() throws {
        #expect(
            try InputProtocol.decode("complete\t10\t/repo\t4\tgit ").message
                == .complete(seq: 10, InputLine(text: "git ", cursor: 4)))
        #expect(try InputProtocol.decode("history\t11\t/repo\tswi").message == .history(seq: 11, query: "swi"))
        #expect(try InputProtocol.decode("bye").message == .bye)
    }

    @Test func decodesEmptyBuffer() throws {
        #expect(try InputProtocol.decode("line\t1\t/\t0\t").message == .line(seq: 1, InputLine(text: "", cursor: 0)))
    }

    @Test func escapesRoundTrip() throws {
        let text = "printf 'a\tb\\n'\nsecond line \\ end"
        let encoded = InputProtocol.encode(
            ShellPacket(.line(seq: 3, InputLine(text: text, cursor: 2)), directory: "/a\tb"))

        let decoded = try InputProtocol.decode(try #require(encoded))

        #expect(decoded == ShellPacket(.line(seq: 3, InputLine(text: text, cursor: 2)), directory: "/a\tb"))
        #expect(encoded?.contains("\n") == false)
    }

    @Test func unknownVerbThrowsWithTheLine() {
        #expect(throws: InputProtocolError(line: "jump\t1", cause: "unknown message \"jump\"")) {
            try InputProtocol.decode("jump\t1")
        }
    }

    @Test func missingFieldThrows() {
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("line\t1\t/\t2") }
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("done\t1") }
    }

    @Test func nonNumericFieldThrows() {
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("done\tx\t0") }
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("hello\tnot-a-uuid") }
    }

    @Test func lineOverLimitIsNotEncoded() {
        let text = String(repeating: "a", count: InputProtocol.maxLineBytes + 1)

        #expect(
            InputProtocol.encode(ShellPacket(.line(seq: 1, InputLine(text: text, cursor: 0)), directory: "/")) == nil)
    }

    @Test func encodesSuggestAndEdit() {
        #expect(InputProtocol.encode(SmaltiMessage.suggest(seq: 4, "eckout\tx")) == "suggest\t4\teckout\\tx")
        #expect(
            InputProtocol.encode(SmaltiMessage.edit(seq: 5, InputLine(text: "git checkout ", cursor: 13)))
                == "edit\t5\t13\tgit checkout ")
    }

    @Test func encodesFallback() {
        #expect(InputProtocol.encode(SmaltiMessage.fallback(seq: 7)) == "fallback\t7")
    }

    @Test func specsListIsSpaceSeparated() {
        #expect(InputProtocol.encode(SmaltiMessage.specs(["git", "npm", "swift"])) == "specs\tgit npm swift")
    }

    // Block 4 review I4: zsh names its directory in each message, so a `cd` never races OSC 7.
    @Test func directoryTravelsWithTheMessage() throws {
        let packet = try InputProtocol.decode("line\t2\t/Users/s/proj\t2\tls")

        #expect(packet.directory == "/Users/s/proj")
    }

    @Test func messagesWithoutADirectoryHaveNone() throws {
        #expect(try InputProtocol.decode("done\t3\t0").directory == nil)
        #expect(try InputProtocol.decode("hello\t6F2B4E1C-0A3D-4C5E-9F11-2233445566AA").directory == nil)
    }

    // Block 4 review m1: ⌘↩ marks its edit, so zsh can refuse the Return that follows a dropped one.
    @Test func editThatRunsIsMarked() {
        #expect(
            InputProtocol.encode(SmaltiMessage.edit(seq: 5, InputLine(text: "ls", cursor: 2), thenEnter: true))
                == "editrun\t5\t2\tls")
    }

    // Final review m9: hundreds of specs go out in several `specs` answers, each under the answer cap.
    @Test func longSpecListIsSplitUnderTheCap() {
        let commands = (0..<800).map { "command-\($0)" }

        let messages = InputProtocol.specMessages(commands)
        let encoded = messages.map(InputProtocol.encode)
        let sent = messages.flatMap { message -> [String] in
            if case .specs(let part) = message { return part }
            return []
        }

        #expect(messages.count > 1)
        #expect(encoded.allSatisfy { $0.utf8.count + 1 <= InputProtocol.maximumAnswerBytes })
        #expect(sent == commands)
    }

    @Test func noSpecsIsStillOneAnswer() {
        #expect(InputProtocol.specMessages([]) == [.specs([])])
    }

    // Mutation survivors (F4 close).
    @Test func shortSpecListIsOneAnswer() {
        #expect(InputProtocol.specMessages(["git", "npm"]) == [.specs(["git", "npm"])])
    }

    @Test func fieldStartingWithNIsNotANewline() throws {
        let packet = try InputProtocol.decode("history\t3\t/tmp\tnano")

        #expect(packet.message == .history(seq: 3, query: "nano"))
    }
}
