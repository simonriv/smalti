import Foundation
import SmaltiCore
import Testing

@Suite("InputProtocol")
struct InputProtocolTests {
    private let pane = PaneID(rawValue: UUID(uuidString: "6F2B4E1C-0A3D-4C5E-9F11-2233445566AA") ?? UUID())

    @Test func decodesHello() throws {
        let message = try InputProtocol.decode("hello\t6F2B4E1C-0A3D-4C5E-9F11-2233445566AA")

        #expect(message == .hello(pane))
    }

    @Test func decodesLine() throws {
        let message = try InputProtocol.decode("line\t7\t3\tgit ch")

        #expect(message == .line(seq: 7, InputLine(text: "git ch", cursor: 3)))
    }

    @Test func decodesExecAndDone() throws {
        #expect(try InputProtocol.decode("exec\t8\tswift test") == .exec(seq: 8, command: "swift test"))
        #expect(try InputProtocol.decode("done\t9\t127") == .done(seq: 9, exit: 127))
    }

    @Test func decodesCompleteHistoryAndBye() throws {
        #expect(
            try InputProtocol.decode("complete\t10\t4\tgit ")
                == .complete(seq: 10, InputLine(text: "git ", cursor: 4)))
        #expect(try InputProtocol.decode("history\t11\tswi") == .history(seq: 11, query: "swi"))
        #expect(try InputProtocol.decode("bye") == .bye)
    }

    @Test func decodesEmptyBuffer() throws {
        #expect(try InputProtocol.decode("line\t1\t0\t") == .line(seq: 1, InputLine(text: "", cursor: 0)))
    }

    @Test func escapesRoundTrip() throws {
        let text = "printf 'a\tb\\n'\nsecond line \\ end"
        let encoded = InputProtocol.encode(ShellMessage.line(seq: 3, InputLine(text: text, cursor: 2)))

        let decoded = try InputProtocol.decode(try #require(encoded))

        #expect(decoded == .line(seq: 3, InputLine(text: text, cursor: 2)))
        #expect(encoded?.contains("\n") == false)
    }

    @Test func unknownVerbThrowsWithTheLine() {
        #expect(throws: InputProtocolError(line: "jump\t1", cause: "unknown message \"jump\"")) {
            try InputProtocol.decode("jump\t1")
        }
    }

    @Test func missingFieldThrows() {
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("line\t1\t2") }
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("done\t1") }
    }

    @Test func nonNumericFieldThrows() {
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("done\tx\t0") }
        #expect(throws: InputProtocolError.self) { try InputProtocol.decode("hello\tnot-a-uuid") }
    }

    @Test func lineOverLimitIsNotEncoded() {
        let text = String(repeating: "a", count: InputProtocol.maxLineBytes + 1)

        #expect(InputProtocol.encode(ShellMessage.line(seq: 1, InputLine(text: text, cursor: 0))) == nil)
    }

    @Test func encodesSuggestAndEdit() {
        #expect(InputProtocol.encode(SmaltiMessage.suggest(seq: 4, "eckout\tx")) == "suggest\t4\teckout\\tx")
        #expect(
            InputProtocol.encode(SmaltiMessage.edit(seq: 5, InputLine(text: "git checkout ", cursor: 13)))
                == "edit\t5\t13\tgit checkout ")
    }

    @Test func encodesRunAndFallback() {
        #expect(InputProtocol.encode(SmaltiMessage.run(seq: 6)) == "run\t6")
        #expect(InputProtocol.encode(SmaltiMessage.fallback(seq: 7)) == "fallback\t7")
    }

    @Test func specsListIsSpaceSeparated() {
        #expect(InputProtocol.encode(SmaltiMessage.specs(["git", "npm", "swift"])) == "specs\tgit npm swift")
    }
}
